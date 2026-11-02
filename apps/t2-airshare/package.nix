# t2-airshare: Quick Share (Android) and AirDrop (through t2-drop) for T2
# Macs — a GTK4/libadwaita app (`t2-airshare`), its receiver daemon/CLI
# (`t2airshare`), and the root helper `t2-quickshare-hotspot` that moves a
# Bluetooth Quick Share transfer onto a Wi-Fi hotspot. build.rs compiles the
# Nearby protobufs with protox, so no protoc is needed.
#
# Mirrors the Makefile's `install`:
#   * bin/t2-airshare, bin/t2airshare, libexec/t2-quickshare-hotspot
#   * the app and "Send with T2 AirShare" .desktop files, the icon, the
#     KDE service menu, the Nemo action and the Nautilus-python extension,
#     each with /usr/local/bin rewritten to $out/bin
#   * the user unit systemd/t2-airshare.service → lib/systemd/user, ExecStart
#     rewritten. Shipped as a file (not re-declared in the NixOS module) on
#     purpose: the app's receive toggle runs `systemctl --user enable/disable`
#     on it, which needs the unit's own [Install] section.
#   * the hotspot's bus policy + activation file → share/dbus-1 (the
#     activation file only names SystemdService=, so it needs no path); its
#     system unit is defined natively by nix/modules/t2-airshare.
#   * THIRD-PARTY-NOTICES and the proto licences → share/licenses.
# integration/migrate-t2-share.sh (rename from T2 Share) is Fedora install
# bookkeeping and not consumed. The wordmarks go to the branding store copies.
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
  pname = "t2-airshare";
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
      files = [ "src/bin/t2-airshare/main.rs" ];
    }}
  '';

  postInstall = ''
    # The hotspot helper lives in libexec, like upstream.
    install -Dm755 "$out/bin/t2-quickshare-hotspot" "$out/libexec/t2-quickshare-hotspot"
    rm "$out/bin/t2-quickshare-hotspot"

    install -Dm644 org.t2airshare.gtk.desktop "$out/share/applications/org.t2airshare.gtk.desktop"
    install -Dm644 integration/org.t2airshare.send.desktop \
      "$out/share/applications/org.t2airshare.send.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2airshare.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2airshare.gtk.svg"
    # 0755 like the Makefile: Plasma 6 skips non-executable service menus.
    install -Dm755 integration/t2-airshare-send.servicemenu.desktop \
      "$out/share/kio/servicemenus/t2-airshare-send.desktop"
    install -Dm644 integration/t2-airshare-send.nemo_action \
      "$out/share/nemo/actions/t2-airshare-send.nemo_action"
    install -Dm644 integration/t2-airshare-send.py \
      "$out/share/nautilus-python/extensions/t2-airshare-send.py"
    for f in \
      "$out/share/applications/org.t2airshare.gtk.desktop" \
      "$out/share/applications/org.t2airshare.send.desktop" \
      "$out/share/kio/servicemenus/t2-airshare-send.desktop" \
      "$out/share/nemo/actions/t2-airshare-send.nemo_action" \
      "$out/share/nautilus-python/extensions/t2-airshare-send.py"; do
      substituteInPlace "$f" --replace-fail '/usr/local/bin/' "$out/bin/"
    done

    install -Dm644 systemd/t2-airshare.service "$out/lib/systemd/user/t2-airshare.service"
    substituteInPlace "$out/lib/systemd/user/t2-airshare.service" \
      --replace-fail '/usr/local/bin/t2airshare' "$out/bin/t2airshare"

    install -Dm644 dbus/org.t2airshare.QuickShareHotspot.conf \
      "$out/share/dbus-1/system.d/org.t2airshare.QuickShareHotspot.conf"
    install -Dm644 dbus/org.t2airshare.QuickShareHotspot.service \
      "$out/share/dbus-1/system-services/org.t2airshare.QuickShareHotspot.service"

    install -Dm644 -t "$out/share/licenses/t2-airshare" \
      THIRD-PARTY-NOTICES.md proto/LICENSE-Apache-2.0 proto/LICENSE-Chromium
  '';

  meta = {
    description = "Quick Share and AirDrop for Linux on T2 Macs";
    mainProgram = "t2-airshare";
    platforms = lib.platforms.linux;
    license = with lib.licenses; [
      gpl3Plus
      asl20 # proto/ (Nearby)
      bsd3 # proto/ (Chromium)
    ];
  };
}
