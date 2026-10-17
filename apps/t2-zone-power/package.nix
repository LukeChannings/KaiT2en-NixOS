# t2-zone-power: applies the SMC's CPU/iGPU/dGPU/forced-idle power-limit steps
# the way macOS does (replaces t2-cpu-control upstream). One binary,
# `t2-zonepower-gtk`: the GTK4/libadwaita monitor GUI, and with `--daemon` the
# root `t2-zonepowerd` that reads t2smc's `smc_plimit_raw` and drives
# cpufreq/intel_powerclamp/i915/amdgpu every 250 ms.
#
# Same shape as t2-smc-control (build.rs compiles the gresource bundle with
# glib-compile-resources from `glib`). The upstream unit
# (systemd/t2-zonepowerd.service) hardcodes /usr/local/bin, so the NixOS module
# defines it natively. The wordmark path is rewritten to the branding store
# copy.
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
  pname = "t2-zone-power";
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
    inherit branding;
    helpers = [ ];
    files = [ "src/gui.rs" ];
  };

  postInstall = ''
    install -Dm644 org.t2zonepower.gtk.desktop \
      "$out/share/applications/org.t2zonepower.gtk.desktop"
    substituteInPlace "$out/share/applications/org.t2zonepower.gtk.desktop" \
      --replace-fail 'Exec=/usr/local/bin/' "Exec=$out/bin/"
    install -Dm644 assets/icons/hicolor/scalable/apps/org.t2zonepower.gtk.svg \
      "$out/share/icons/hicolor/scalable/apps/org.t2zonepower.gtk.svg"
  '';

  meta = {
    description = "SMC power-limit (zone power) daemon and monitor for T2 Macs";
    mainProgram = "t2-zonepower-gtk";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
