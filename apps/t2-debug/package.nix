# t2-debug: live Apple T2 (bridgeOS) debugger over the Instruments
# dtservicehub — a GTK4/libadwaita GUI (`t2-debug`: process top, device info,
# os_log stream) and its CLI (`t2debug`).
#
# It takes the shared bridgeOS transport as a relative path dependency
# (`../../t2-services/shared/protocols/t2-bridgexpc`), so the source is the
# repo filtered to this app + t2-services/shared, laid out as in the tree,
# built from the app's subdirectory. build.rs compiles the icon gresource with
# glib-compile-resources. bridgexpc discovery shells out to ip/ping, so both
# binaries get iproute2 + iputils on PATH.
#
# FHS paths rewritten: the kait2en wordmarks → branding store copies, and the
# .desktop's Exec=/TryExec=/usr/local/bin → $out/bin.
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
  iproute2,
  iputils,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
  root = ../..;
  keep = [
    "apps/t2-debug"
    "t2-services/shared"
  ];
  src = lib.cleanSourceWith {
    name = "t2-debug-source";
    src = lib.cleanSource root;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (toString root + "/") (toString path);
      in
      lib.any (k: rel == k || lib.hasPrefix "${k}/" rel || lib.hasPrefix "${rel}/" k) keep;
  };
in
rustPlatform.buildRustPackage {
  pname = "t2-debug";
  version = "0.1.0";

  inherit src;
  cargoRoot = "apps/t2-debug";
  buildAndTestSubdir = "apps/t2-debug";
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
      files = [ "apps/t2-debug/src/bin/t2-debug.rs" ];
    }}
  '';

  # wrapGAppsHook4 wraps every binary in bin/, the CLI included.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        iproute2
        iputils
      ]
    })
  '';

  postInstall = ''
    cd apps/t2-debug
    install -Dm644 org.t2debug.gtk.desktop "$out/share/applications/org.t2debug.gtk.desktop"
    substituteInPlace "$out/share/applications/org.t2debug.gtk.desktop" \
      --replace-fail '/usr/local/bin/' "$out/bin/"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2debug.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2debug.gtk.svg"
    cd - > /dev/null
  '';

  meta = {
    description = "Live Apple T2 (bridgeOS) debugger: process top, device info and os_log stream";
    mainProgram = "t2-debug";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
