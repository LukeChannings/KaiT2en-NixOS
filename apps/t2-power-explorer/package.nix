# t2-power-explorer: a GTK4/libadwaita GUI that inspects kernel device topology
# and runtime power state. It reads a few privileged sysfs/PCI-config nodes via
# `pkexec $out/libexec/t2-power-explorer-status` (a bash helper) guarded by one
# polkit action (`org.t2powerexplorer.status`, allow_active=yes — no password).
#
# The polkit exec.path triangulation (source const == policy exec.path ==
# on-disk helper) is solved by pointing all three at this derivation's
# $out/libexec — see ../../nix/lib/kait2en-polkit.nix. The status helper only
# reads sysfs and PCI config space (no MSRs/turbostat), so it needs no kernel
# `msr` module.
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
  gawk,
  gnused,
  coreutils,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
  helpers = [ "t2-power-explorer-status" ];
in
rustPlatform.buildRustPackage {
  pname = "t2-power-explorer";
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

  # Rewrite the STATUS_HELPER constant and the wordmark path in the source
  # *before* compiling, so the built binary invokes exactly the path polkit
  # authorises and finds the logo in the store.
  postPatch = polkit.rewriteFhsPaths {
    inherit helpers branding;
    files = [
      "src/diagnostics.rs"
      "src/ui.rs"
    ];
  };

  postInstall = ''
    install -Dm755 t2-power-explorer-status "$out/libexec/t2-power-explorer-status"
    patchShebangs "$out/libexec/t2-power-explorer-status"
    wrapProgram "$out/libexec/t2-power-explorer-status" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gawk
          gnused
        ]
      }

    install -Dm644 org.t2powerexplorer.policy \
      "$out/share/polkit-1/actions/org.t2powerexplorer.policy"

    install -Dm644 org.t2powerexplorer.gtk.desktop \
      "$out/share/applications/org.t2powerexplorer.gtk.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2powerexplorer.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2powerexplorer.gtk.svg"

    ${polkit.rewriteFhsPaths {
      inherit helpers branding;
      files = [ "${builtins.placeholder "out"}/share/polkit-1/actions/org.t2powerexplorer.policy" ];
    }}
  '';

  meta = {
    description = "GTK device topology and runtime power-state explorer for T2 Macs";
    mainProgram = "t2-power-explorer";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
