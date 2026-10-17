# t2-smc-control: a GTK4/libadwaita GUI for SMC temperatures, battery state and
# the SMC RTC on T2 Macs, plus (`--daemon`) the root battery-gauging daemon
# that lifts the charge limit for calibration like macOS powerd does.
#
# Same shape as t2-fan-control: rustPlatform builds the binary, then we
# reproduce the Makefile's install of the desktop entry, icon and theme index.
# The upstream unit (systemd/t2-smc-gaugingd.service) hardcodes
# /usr/local/bin, so the NixOS module defines it natively instead.
#
# FHS paths rewritten in postPatch:
#   * the kait2en wordmark (loaded with a fatal .expect()) → branding store copy
#   * /usr/sbin/hwclock (run via pkexec to write the SMC RTC) → util-linux
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
  util-linux,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
in
rustPlatform.buildRustPackage {
  pname = "t2-smc-control";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    glib
    wrapGAppsHook4
  ];

  buildInputs = [
    glib
    gtk4
    libadwaita
  ];

  postPatch = ''
    ${polkit.rewriteFhsPaths {
      inherit branding;
      helpers = [ ];
      files = [ "src/main.rs" ];
    }}
    substituteInPlace src/main.rs \
      --replace-fail '"/usr/sbin/hwclock"' '"${lib.getExe' util-linux "hwclock"}"'
  '';

  postInstall = ''
    install -Dm644 org.t2smccontrol.gtk.desktop \
      "$out/share/applications/org.t2smccontrol.gtk.desktop"
    substituteInPlace "$out/share/applications/org.t2smccontrol.gtk.desktop" \
      --replace-fail 'Exec=/usr/local/bin/' "Exec=$out/bin/"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2smccontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2smccontrol.gtk.svg"
    install -Dm644 assets/icons/hicolor/index.theme \
      "$out/share/icons/hicolor/index.theme"
  '';

  meta = {
    description = "GTK SMC temperatures, battery and RTC tool for T2 Macs, plus the battery-gauging daemon";
    mainProgram = "t2-smc-control";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
