# t2-dgpu-control: a GTK4/libadwaita GUI to power the discrete AMD GPU on/off on
# MacBookPro15,3 / 16,1 / 16,4. Drives vgaswitcheroo, the gpu-power-prefs EFI
# variable, and AMD power-profile sysfs through two privileged bash helpers
# (contrib/t2-dgpu-control-helper, -status) under pkexec + polkit.
#
# The helpers write /sys/firmware/efi/efivars/gpu-power-prefs-* (efivars must be
# writable) and /sys/kernel/debug/vgaswitcheroo/switch (debugfs, mounted by
# default on NixOS), and toggle systemd units. They use awk + systemctl, so are
# wrapped with those on PATH.
#
# The four systemd units (kait2en-dgpu-off/-suspend/-amdgpu-profile/-resume) are
# NOT installed from the shipped files — they hardcode /usr/local/libexec. The
# NixOS module (../../nix/modules/t2-gpu-control) defines them natively with the
# exact names/semantics the GUI toggles via `systemctl enable/disable`.
#
# polkit exec.path triangulation + wordmark: rewritten to this $out — see
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
    "t2-dgpu-control-helper"
    "t2-dgpu-control-status"
  ];
in
rustPlatform.buildRustPackage {
  pname = "t2-dgpu-control";
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
    install -Dm755 contrib/t2-dgpu-control-helper "$out/libexec/t2-dgpu-control-helper"
    install -Dm755 contrib/t2-dgpu-control-status "$out/libexec/t2-dgpu-control-status"
    patchShebangs "$out/libexec/t2-dgpu-control-helper" "$out/libexec/t2-dgpu-control-status"
    for h in t2-dgpu-control-helper t2-dgpu-control-status; do
      wrapProgram "$out/libexec/$h" \
        --prefix PATH : ${
          lib.makeBinPath [
            gawk
            systemd
            coreutils
          ]
        }
    done

    install -Dm644 contrib/org.t2dgpucontrol.policy \
      "$out/share/polkit-1/actions/org.t2dgpucontrol.gtk.policy"
    install -Dm644 contrib/org.t2dgpucontrol.status.policy \
      "$out/share/polkit-1/actions/org.t2dgpucontrol.gtk.status.policy"

    install -Dm644 org.t2dgpucontrol.gtk.desktop \
      "$out/share/applications/org.t2dgpucontrol.gtk.desktop"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2dgpucontrol.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2dgpucontrol.gtk.svg"

    ${polkit.rewriteFhsPaths {
      inherit helpers branding;
      files = [
        "${builtins.placeholder "out"}/share/polkit-1/actions/org.t2dgpucontrol.gtk.policy"
        "${builtins.placeholder "out"}/share/polkit-1/actions/org.t2dgpucontrol.gtk.status.policy"
      ];
    }}
  '';

  meta = {
    description = "GTK discrete-GPU power control for T2 MacBook Pro models";
    mainProgram = "t2-dgpu-control";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
