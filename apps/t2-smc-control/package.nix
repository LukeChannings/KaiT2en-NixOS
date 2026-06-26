# t2-smc-control: a GTK4/libadwaita GUI for SMC temperatures and the battery
# charge limit on T2 Macs.
#
# Same shape as t2-fan-control: rustPlatform builds the binary, then we
# reproduce the Makefile's install of the desktop entry, icon and theme index.
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
}:

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

  postInstall = ''
    install -Dm644 org.t2smccontrol.gtk.desktop \
      "$out/share/applications/org.t2smccontrol.gtk.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2smccontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2smccontrol.gtk.svg"
    install -Dm644 assets/icons/hicolor/index.theme \
      "$out/share/icons/hicolor/index.theme"
  '';

  meta = {
    description = "GTK SMC temperatures and battery charge limit control for T2 Macs";
    mainProgram = "t2-smc-control";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
