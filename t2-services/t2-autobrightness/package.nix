# t2-autobrightness: macOS-like automatic display brightness for T2 Macs —
# reads the ambient light sensor (IIO), drives the panel through GNOME Shell's
# org.gnome.Shell.Brightness with smooth transitions, and learns from manual
# changes. GNOME-only for now.
#
# Upstream's Makefile also installs integration/systemd/
# kait2en-t2-autobrightness.service (a *user* unit, @BINDIR@-templated) and the
# GNOME Shell extension kait2en-autobrightness@kait2en, which keeps the
# brightness slider in sync. The unit is defined natively by
# nix/modules/t2-autobrightness; the extension ships under
# share/gnome-shell/extensions, where GNOME finds it through the system
# profile. The daemon enables the extension and switches GNOME's own
# automatic brightness off with `gsettings`, so glib's bin is on its PATH.
{
  lib,
  rustPlatform,
  makeWrapper,
  glib,
}:

rustPlatform.buildRustPackage {
  pname = "t2-autobrightness";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    uuid=kait2en-autobrightness@kait2en
    install -Dm644 -t "$out/share/gnome-shell/extensions/$uuid" \
      "integration/gnome-shell/$uuid/extension.js" \
      "integration/gnome-shell/$uuid/metadata.json"
    wrapProgram "$out/bin/t2-autobrightness" \
      --prefix PATH : ${lib.makeBinPath [ glib.bin ]}
  '';

  passthru.extensionUuid = "kait2en-autobrightness@kait2en";

  meta = {
    description = "Automatic display brightness for T2 Intel Macs that follows the macOS behaviour";
    mainProgram = "t2-autobrightness";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
