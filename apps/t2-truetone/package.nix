# t2-truetone: True Tone for T2 Macs under GNOME — adapts the display white
# point to the ambient light, adds an evening mode, and carries the automatic
# brightness that used to be t2-services/t2-autobrightness (which it
# replaced). `t2-truetone` is the GTK4/libadwaita settings app, `t2truetone`
# the session daemon and CLI (`daemon|status|sensor`). It reads the T2's
# ambient light sensor (USB HID 05ac:8262) through hidraw and drives the
# panel through Mutter and GNOME Shell.
#
# Mirrors the Makefile's `install`:
#   * bin/t2-truetone, bin/t2truetone
#   * the .desktop file (Exec/TryExec rewritten to $out/bin) and the icon
#   * the user unit systemd/t2-truetone.service → lib/systemd/user, ExecStart
#     rewritten. Shipped as a file (not re-declared in the NixOS module) on
#     purpose: the app's Start/Stop button runs `systemctl --user
#     enable|disable --now` on it, which needs the unit's own [Install]
#     section — the same exception as t2-airshare.
#   * udev/70-t2-truetone.rules → lib/udev/rules.d (uaccess on the sensor's
#     hidraw node, so the session daemon can open it)
#   * the GNOME Shell extension kait2en-autobrightness@kait2en (same UUID as
#     before; the daemon enables it) → share/gnome-shell/extensions.
# The daemon reads and writes GNOME settings with `gsettings`, so glib's bin
# is on the PATH of both binaries.
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
  pname = "t2-truetone";
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
    install -Dm644 org.t2truetone.gtk.desktop "$out/share/applications/org.t2truetone.gtk.desktop"
    substituteInPlace "$out/share/applications/org.t2truetone.gtk.desktop" \
      --replace-fail /usr/local/bin/t2-truetone "$out/bin/t2-truetone"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2truetone.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2truetone.gtk.svg"

    install -Dm644 systemd/t2-truetone.service "$out/lib/systemd/user/t2-truetone.service"
    substituteInPlace "$out/lib/systemd/user/t2-truetone.service" \
      --replace-fail /usr/local/bin/t2truetone "$out/bin/t2truetone"

    install -Dm644 udev/70-t2-truetone.rules "$out/lib/udev/rules.d/70-t2-truetone.rules"

    uuid=kait2en-autobrightness@kait2en
    install -Dm644 -t "$out/share/gnome-shell/extensions/$uuid" \
      "integration/gnome-shell/$uuid/extension.js" \
      "integration/gnome-shell/$uuid/metadata.json"
  '';

  # wrapGAppsHook4 wraps both binaries; put gsettings on their PATH too.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ glib.bin ]})
  '';

  passthru.extensionUuid = "kait2en-autobrightness@kait2en";

  meta = {
    description = "Ambient white point, evening mode and automatic brightness for T2 Macs under GNOME";
    mainProgram = "t2-truetone";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
