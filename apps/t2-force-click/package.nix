# t2-force-click: GTK4/libadwaita GUI + root daemon for the T2 trackpad's Force
# Click (thresholds/click strength on t2_precision_trackpad, plus a
# configurable deep-press action). The daemon (`--daemon`) owns the driver
# parameters and serves the GUI on /run/t2-force-click/daemon.sock.
#
# FHS paths rewritten in postPatch:
#   * the kait2en wordmark → branding store copy
#   * the daemon's config /etc/t2-force-click/config.txt →
#     /var/lib/t2-force-click/config.txt (persistent state belongs in
#     /var/lib on NixOS; the NixOS module provides it as StateDirectory)
# The upstream unit (systemd/t2-force-click.service) hardcodes /usr/local/bin,
# so the NixOS module defines it natively.
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
in
rustPlatform.buildRustPackage {
  pname = "t2-force-click";
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
    substituteInPlace src/config.rs \
      --replace-fail '"/etc/t2-force-click/config.txt"' '"/var/lib/t2-force-click/config.txt"'
  '';

  postInstall = ''
    install -Dm644 org.t2forceclick.gtk.desktop \
      "$out/share/applications/org.t2forceclick.gtk.desktop"
    substituteInPlace "$out/share/applications/org.t2forceclick.gtk.desktop" \
      --replace-fail 'Exec=/usr/local/bin/' "Exec=$out/bin/"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2forceclick.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2forceclick.gtk.svg"
  '';

  meta = {
    description = "Force Click settings GUI and daemon for the Apple T2 trackpad";
    mainProgram = "t2-force-click";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
