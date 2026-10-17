# t2-touchid: bridges the Apple T2 Touch ID sensor to stock fprintd through
# libfprint's virtual storage device socket, talking BiometricKit to the SEP
# over the NCM link (shared t2-bridgexpc transport). Watches Esc via libinput
# and broadcasts its prompt state on the system bus (org.kait2en.TouchId) for
# the Touch Bar.
#
# Upstream's Makefile installs integration/systemd/kait2en-t2-touchid.service
# (@BINDIR@-templated, EnvironmentFile=/etc/kait2en/t2-touchid.conf), the
# fprintd.service drop-in, the D-Bus policy and the default config. The units
# are defined natively by nix/modules/t2-services; the D-Bus policy and the
# default config are shipped under $out for it. The SELinux policy is
# Fedora-only and not consumed.
{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  libinput,
  systemdLibs,
  fprintd,
  iproute2,
  iputils,
}:

rustPlatform.buildRustPackage {
  pname = "t2-touchid";
  version = "0.1.0";

  src = import ../../nix/lib/t2-services-src.nix { inherit lib; } "t2-touchid";
  cargoRoot = "t2-touchid";
  buildAndTestSubdir = "t2-touchid";
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    libinput
    systemdLibs
  ];

  postInstall = ''
    # `fprintd-enroll` for automatic binding; ip/ping for bridgexpc discovery.
    wrapProgram "$out/bin/t2-touchid" \
      --prefix PATH : ${
        lib.makeBinPath [
          fprintd
          iproute2
          iputils
        ]
      }

    install -Dm644 t2-touchid/integration/dbus/org.kait2en.TouchId.conf \
      "$out/share/dbus-1/system.d/org.kait2en.TouchId.conf"
    install -Dm644 t2-touchid/config/t2-touchid.conf \
      "$out/share/t2-touchid/t2-touchid.conf"
  '';

  meta = {
    description = "Apple T2 Touch ID bridge for fprintd";
    mainProgram = "t2-touchid";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
