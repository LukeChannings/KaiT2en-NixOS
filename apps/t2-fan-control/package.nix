# t2-fan-control: a GTK4/libadwaita fan-control GUI + daemon for T2 Macs.
#
# The in-repo Makefile drives `cargo build --release` then `install`s the
# binary, a `.desktop` file, an icon, and a systemd unit into a PREFIX. Here we
# let rustPlatform build the binary, then reproduce the Makefile's install side
# effects against `$out` (no systemctl/gtk-update-icon-cache — NixOS handles
# those at activation time).
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
  pname = "t2-fancontrol-gtk";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # glib-compile-resources runs from build.rs; pkg-config + the GTK stack are
  # the C deps the gtk4/libadwaita crates link against.
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

  # Install the non-binary artifacts the Makefile installs (desktop entry,
  # icon, hicolor theme index, systemd unit), into the standard Nix layout.
  postInstall = ''
    install -Dm644 org.t2fancontrol.gtk.desktop \
      "$out/share/applications/org.t2fancontrol.gtk.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2fancontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2fancontrol.gtk.svg"
    install -Dm644 assets/icons/hicolor/index.theme \
      "$out/share/icons/hicolor/index.theme"
    install -Dm644 systemd/t2-fancontrol.service \
      "$out/lib/systemd/system/t2-fancontrol.service"
  '';

  meta = {
    description = "GTK fan control for T2 Macs on Linux";
    mainProgram = "t2-fancontrol-gtk";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
