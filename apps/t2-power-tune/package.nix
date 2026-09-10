# t2-power-tune: a Python 3 / PyGObject (GTK4/libadwaita) GUI for PCIe ASPM and
# power-saving tunables. No compile step — install the scripts and wrap them.
#
# Two privileged helpers run via pkexec + polkit (org.t2powertune.policy):
#   * t2-power-tune-helper (python3) — configure=auth_admin_keep; drives
#     lspci/setpci/systemctl, so it is wrapped with those on PATH.
#   * t2-power-tune-status (python3) — status=allow_active; reads pmc_core
#     debugfs C-state counters, no external tools.
#
# The GUI is wrapped by wrapGAppsHook4 (GI_TYPELIB_PATH etc. for gtk4/libadwaita
# and the `gi` python module from pygobject3). The polkit exec.path
# triangulation and wordmark path are rewritten to this derivation's $out — see
# ../../nix/lib/kait2en-polkit.nix.
{
  lib,
  stdenv,
  python3,
  gtk4,
  libadwaita,
  glib,
  gobject-introspection,
  wrapGAppsHook4,
  makeWrapper,
  pciutils,
  systemd,
  coreutils,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
  helpers = [
    "t2-power-tune-helper"
    "t2-power-tune-status"
  ];
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
  out = builtins.placeholder "out";
in
stdenv.mkDerivation {
  pname = "t2-power-tune";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
    makeWrapper
  ];

  buildInputs = [
    pythonEnv
    gtk4
    libadwaita
    glib
  ];

  dontBuild = true;

  # Wrap the GUI and the python helper ourselves (the status helper needs no
  # PATH beyond python); don't let wrapGAppsHook4 auto-wrap the libexec scripts.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 t2-power-tune.py "$out/bin/t2-power-tune"
    install -Dm755 t2-power-tune-helper "$out/libexec/t2-power-tune-helper"
    install -Dm755 t2-power-tune-status "$out/libexec/t2-power-tune-status"
    install -Dm644 org.t2powertune.policy \
      "$out/share/polkit-1/actions/org.t2powertune.policy"
    install -Dm644 org.t2powertune.gtk.desktop \
      "$out/share/applications/org.t2powertune.gtk.desktop"
    install -Dm644 org.t2powertune.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2powertune.gtk.svg"

    # HELPER/STATUS constants (.py), the helper's self-reference and the two
    # policy exec.path entries, plus the wordmark path -> this store output.
    ${polkit.rewriteFhsPaths {
      inherit helpers branding;
      files = [
        "${out}/bin/t2-power-tune"
        "${out}/libexec/t2-power-tune-helper"
        "${out}/share/polkit-1/actions/org.t2powertune.policy"
      ];
    }}

    # The desktop entry hardcodes /usr/local/bin; repoint at the store binary.
    substituteInPlace "$out/share/applications/org.t2powertune.gtk.desktop" \
      --replace-quiet /usr/local/bin/t2-power-tune "$out/bin/t2-power-tune"

    # The helper generates systemd ExecStart strings referencing FHS tool paths
    # that do not exist on NixOS; repoint them at store binaries.
    substituteInPlace "$out/libexec/t2-power-tune-helper" \
      --replace-quiet /usr/bin/setpci "${pciutils}/bin/setpci" \
      --replace-quiet /usr/bin/printf "${coreutils}/bin/printf"

    patchShebangs "$out/bin/t2-power-tune" \
      "$out/libexec/t2-power-tune-helper" \
      "$out/libexec/t2-power-tune-status"

    runHook postInstall
  '';

  # gappsWrapperArgs is populated by wrapGAppsHook4 in preFixup.
  preFixup = ''
    wrapProgram "$out/bin/t2-power-tune" "''${gappsWrapperArgs[@]}"
    wrapProgram "$out/libexec/t2-power-tune-helper" \
      --prefix PATH : ${
        lib.makeBinPath [
          pciutils
          systemd
        ]
      }
  '';

  meta = {
    description = "GTK PCIe ASPM and power-saving tuner for T2 Macs";
    mainProgram = "t2-power-tune";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
