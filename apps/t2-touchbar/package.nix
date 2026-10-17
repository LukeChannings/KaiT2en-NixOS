# kait2en-touchbar (apps/t2-touchbar): the dark-first T2 Touch Bar daemon,
# which replaced react-drm upstream. A Rust DRM/libinput client that renders
# the bar on the Touch Bar's own DRM card, plus a root `--attach` mode that
# switches the 05ac:8302 USB device to its display configuration.
#
# Upstream's Makefile installs the binary, the systemd user/system units, the
# udev rules and the default /etc/kait2en/touchbar.toml. The units hardcode
# /usr/local/bin, so the NixOS module (nix/modules/t2-touchbar) defines them
# natively; we ship the udev rules (with /bin/chgrp|chmod rewritten to
# coreutils) and the default config under $out for it to consume.
#
# FHS paths rewritten in postPatch: the renderer's Fedora font path for Adwaita
# Sans → nixpkgs adwaita-fonts (the Inter/Cantarell fallbacks are left as-is;
# the first one now always resolves).
{
  lib,
  rustPlatform,
  pkg-config,
  libinput,
  systemdLibs,
  adwaita-fonts,
  coreutils,
}:

rustPlatform.buildRustPackage {
  pname = "kait2en-touchbar";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libinput
    systemdLibs
  ];

  postPatch = ''
    substituteInPlace src/renderer.rs \
      --replace-fail '"/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf"' \
                     '"${adwaita-fonts}/share/fonts/Adwaita/AdwaitaSans-Regular.ttf"'
  '';

  postInstall = ''
    install -Dm644 integration/udev/99-zz-kait2en-touchbar.rules \
      "$out/lib/udev/rules.d/99-zz-kait2en-touchbar.rules"
    substituteInPlace "$out/lib/udev/rules.d/99-zz-kait2en-touchbar.rules" \
      --replace-fail '/bin/chgrp' '${coreutils}/bin/chgrp' \
      --replace-fail '/bin/chmod' '${coreutils}/bin/chmod'
    install -Dm644 config/touchbar.toml "$out/share/kait2en-touchbar/touchbar.toml"
    install -Dm644 THIRD-PARTY-NOTICES.md \
      "$out/share/licenses/kait2en-touchbar/THIRD-PARTY-NOTICES.md"
  '';

  meta = {
    description = "Dark-first Touch Bar daemon for Apple T2 Macs";
    mainProgram = "kait2en-touchbar";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl3Plus;
  };
}
