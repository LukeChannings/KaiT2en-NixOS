# t2-hybrid-gpu-control: a GTK4/libadwaita GUI to switch the hybrid graphics on
# the MacBookPro15,1 (Intel iGPU + AMD dGPU via vgaswitcheroo / gpu-power-prefs
# EFI variable). Two privileged bash helpers under pkexec + polkit.
#
# Unlike t2-dgpu-control this ships NO systemd units — it keeps state in
# /run/t2-hybrid-gpu-control and its Makefile removes the dgpu units as legacy.
# The NixOS module therefore defines no units and, when the hybrid profile is
# selected, ensures the dgpu units are absent.
#
# The helpers use awk + systemctl and write efivars/vgaswitcheroo. polkit
# exec.path triangulation + wordmark are rewritten to this $out — see
# ../../nix/lib/kait2en-polkit.nix.
{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
  gawk,
  systemd,
  coreutils,
  branding,
}:

let
  polkit = import ../../nix/lib/kait2en-polkit.nix { inherit lib; };
  helpers = [
    "t2-hybrid-gpu-control-helper"
    "t2-hybrid-gpu-control-status"
  ];
in
rustPlatform.buildRustPackage {
  pname = "t2-hybrid-gpu-control";
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

  postPatch = polkit.rewriteFhsPaths {
    inherit helpers branding;
    files = [ "src/main.rs" ];
  };

  postInstall = ''
    install -Dm755 contrib/t2-hybrid-gpu-control-helper "$out/libexec/t2-hybrid-gpu-control-helper"
    install -Dm755 contrib/t2-hybrid-gpu-control-status "$out/libexec/t2-hybrid-gpu-control-status"
    patchShebangs "$out/libexec/t2-hybrid-gpu-control-helper" "$out/libexec/t2-hybrid-gpu-control-status"
    for h in t2-hybrid-gpu-control-helper t2-hybrid-gpu-control-status; do
      wrapProgram "$out/libexec/$h" \
        --prefix PATH : ${
          lib.makeBinPath [
            gawk
            systemd
            coreutils
          ]
        }
    done

    install -Dm644 contrib/org.t2hybridgpucontrol.policy \
      "$out/share/polkit-1/actions/org.t2hybridgpucontrol.gtk.policy"
    install -Dm644 contrib/org.t2hybridgpucontrol.status.policy \
      "$out/share/polkit-1/actions/org.t2hybridgpucontrol.gtk.status.policy"

    install -Dm644 org.t2hybridgpucontrol.gtk.desktop \
      "$out/share/applications/org.t2hybridgpucontrol.gtk.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2hybridgpucontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2hybridgpucontrol.gtk.svg"

    ${polkit.rewriteFhsPaths {
      inherit helpers branding;
      files = [
        "${builtins.placeholder "out"}/share/polkit-1/actions/org.t2hybridgpucontrol.gtk.policy"
        "${builtins.placeholder "out"}/share/polkit-1/actions/org.t2hybridgpucontrol.gtk.status.policy"
      ];
    }}
  '';

  meta = {
    description = "GTK hybrid-graphics control for the T2 MacBookPro15,1";
    mainProgram = "t2-hybrid-gpu-control";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
