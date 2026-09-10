# t2-cpu-control: a Python 3 / PyGObject (GTK4/libadwaita) GUI for CPU power
# limits (RAPL PL1/PL2), turbo, and the MSR_TEMPERATURE_TARGET TCC offset, plus
# thermal telemetry. Same Python packaging shape as t2-power-tune.
#
# Three privileged bash helpers run via pkexec + polkit (org.t2cpucontrol.policy):
#   * t2-cpu-control-helper  — configure=auth_admin_keep; rdmsr/wrmsr/modprobe/
#     systemctl. Persists saved limits so they can be re-applied at boot/resume.
#   * t2-cpu-control-status  — status=allow_active; rdmsr/modprobe telemetry.
#   * t2-cpu-kernel-benchmark — a calibration stressor (make/gcc/curl/tar); wrapped
#     best-effort (its kernel-source fetch is otherwise Fedora-specific).
#
# State-path fix: the helper writes its saved config to /etc/t2-cpu-control.conf,
# which is read-only on NixOS. We redirect it to /var/lib/t2-cpu-control/config
# (alongside its existing PERSISTENT_STATE_DIR=/var/lib/t2-cpu-control); the
# NixOS module creates that dir via tmpfiles. /run/t2-cpu-control is tmpfs and
# needs no change.
#
# The apply-saved boot service and the resume hook are defined natively by the
# NixOS module (../../nix/modules/t2-cpu-control), pointing at
# $out/libexec/t2-cpu-control-helper — the raw unit files are not shipped.
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
  msr-tools,
  kmod,
  systemd,
  coreutils,
  curl,
  gnutar,
  gnumake,
  gcc,
  xz,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
  helpers = [
    "t2-cpu-control-helper"
    "t2-cpu-control-status"
    "t2-cpu-kernel-benchmark"
  ];
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
  out = builtins.placeholder "out";
in
stdenv.mkDerivation {
  pname = "t2-cpu-control";
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
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 t2-cpu-control.py "$out/bin/t2-cpu-control"
    install -Dm755 t2-cpu-control-helper "$out/libexec/t2-cpu-control-helper"
    install -Dm755 t2-cpu-control-status "$out/libexec/t2-cpu-control-status"
    install -Dm755 t2-cpu-kernel-benchmark "$out/libexec/t2-cpu-kernel-benchmark"
    install -Dm644 org.t2cpucontrol.policy \
      "$out/share/polkit-1/actions/org.t2cpucontrol.policy"
    install -Dm644 org.t2cpucontrol.gtk.desktop \
      "$out/share/applications/org.t2cpucontrol.gtk.desktop"
    install -Dm644 org.t2cpucontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2cpucontrol.gtk.svg"

    # HELPER/STATUS/BENCHMARK constants, the two policy exec.path entries and
    # the wordmark path -> this store output.
    ${polkit.rewriteFhsPaths {
      inherit helpers branding;
      files = [
        "${out}/bin/t2-cpu-control"
        "${out}/share/polkit-1/actions/org.t2cpucontrol.policy"
      ];
    }}

    # Redirect the saved-config path off read-only /etc onto the writable state
    # dir the module provisions.
    substituteInPlace "$out/libexec/t2-cpu-control-helper" \
      --replace-fail /etc/t2-cpu-control.conf /var/lib/t2-cpu-control/config

    # Desktop entry hardcodes /usr/local/bin; repoint at the store binary.
    substituteInPlace "$out/share/applications/org.t2cpucontrol.gtk.desktop" \
      --replace-quiet /usr/local/bin/t2-cpu-control "$out/bin/t2-cpu-control"

    patchShebangs "$out/bin/t2-cpu-control" \
      "$out/libexec/t2-cpu-control-helper" \
      "$out/libexec/t2-cpu-control-status" \
      "$out/libexec/t2-cpu-kernel-benchmark"

    runHook postInstall
  '';

  preFixup = ''
    wrapProgram "$out/bin/t2-cpu-control" "''${gappsWrapperArgs[@]}"
    wrapProgram "$out/libexec/t2-cpu-control-helper" \
      --prefix PATH : ${
        lib.makeBinPath [
          msr-tools
          kmod
          systemd
          coreutils
        ]
      }
    wrapProgram "$out/libexec/t2-cpu-control-status" \
      --prefix PATH : ${
        lib.makeBinPath [
          msr-tools
          kmod
          coreutils
        ]
      }
    wrapProgram "$out/libexec/t2-cpu-kernel-benchmark" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          curl
          gnutar
          gnumake
          gcc
          xz
        ]
      }
  '';

  meta = {
    description = "GTK CPU power-limit and thermal control for T2 Macs";
    mainProgram = "t2-cpu-control";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
