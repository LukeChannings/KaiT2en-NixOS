# KaiT2en profile for the MacBookPro16,1 (T2, 2019 16" MacBook Pro).
#
# Turns on everything upstream's installer sets up on this machine: the
# out-of-tree T2 kernel drivers, Wi-Fi/Bluetooth firmware, the suspend/resume
# and RTC fixes, the T2 bridge services (AVE, Touch ID), the Touch Bar daemon,
# the fan/SMC/power/Force Click apps, hybrid graphics (the gpu-runtime-pm
# amdgpu + t2-hybrid-gpu-control) and this model's audio DSP profile
# ("16_1"). Import it from your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookpro16-1 ];
#
# Notes:
#   * hardware.kait2en.firmware is unfree and builds inside a VM — set
#     nixpkgs.config.allowUnfree = true (or allowlist "brcm-firmware") and have
#     KVM available, or set hardware.kait2en.firmware.enable = false if you copy
#     the Broadcom blobs in by hand instead.
#   * Touch ID: log into macOS once after a T2 power loss so the SEP unlocks,
#     then bind your finger with `fprintd-enroll` (or set
#     services.t2-touchid.bindUser = "<you>"; to bind automatically).
#   * The Touch Bar needs your user in the kait2en-touchbar group:
#     services.t2-touchbar.users = [ "<you>" ];
{ lib, pkgs, ... }:

{
  imports = [ ./default.nix ];

  hardware.kait2en = {
    enable = true;
    firmware.enable = true;
    # The Navi 14 (Radeon Pro 5300M/5500M) drops off the PCIe bus under load
    # with forced ASPM: upstream leaves amdgpu.aspm, pcie_aspm=force and the
    # powersave policy off on this model and lets firmware/amdgpu decide.
    amdgpuAspm = false;
    pcieAspm = "firmware";
    # install-apps.sh: t2-hybrid-gpu-control on this model, on top of the
    # gpu-runtime-pm amdgpu (GMUX runtime PM, Navi 14 UCLK cap).
    gpuRuntimePm.enable = true;
    gpuControl.mode = "hybrid";
  };

  services.t2-touchbar.enable = true;
  services.kait2en-suspend.enable = true;
  services.kait2en-rtc-sync.enable = true;
  # Shared bridge-link integration (NM "Apple T2 Bridge" link-local profile +
  # suspend hook runner), and the bridgeOS services upstream installs on every
  # T2 Mac: AVE (t2remote) and the Touch ID bridge for fprintd.
  services.t2-services.enable = true;
  services.t2-ave.enable = true;
  services.t2-touchid.enable = true;
  services.t2-fan-control.enable = true;
  services.t2-smc-control.enable = true;
  services.t2-power-explorer.enable = true;
  services.t2-power-tune.enable = true;
  services.t2-zone-power.enable = true;
  services.t2-force-click.enable = true;

  services.t2-journal.enable = true;

  services.t2bce-audio-dsp = {
    enable = true;
    model = "16_1";
  };

  # Hybrid-graphics boot plumbing (dGPU runtime PM + iGPU-primary udev rules,
  # switcheroo) comes from gpuControl.mode = "hybrid" above — see
  # ../modules/t2-gpu-control.

  # VA-API video decode on the iGPU that scans out: without the iHD driver
  # browsers fall back to CPU software decode. Deliberately not routing decode
  # to the dGPU — that would defeat the hybrid runtime PM.
  hardware.graphics = {
    enable = lib.mkDefault true;
    enable32Bit = lib.mkDefault true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      intel-compute-runtime
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
    ];
  };
  # Pin libva to iHD so it doesn't probe (and fail on) other backends.
  environment.sessionVariables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";

  # ── Clear stuck BD PROCHOT ──────────────────────────────────────────
  # The i9-9880H ships with bidirectional PROCHOT enabled (MSR_POWER_CTL 0x1FC
  # bit0) and an external agent (VRM/dGPU/T2) leaves the PROCHOT line asserted
  # even when the package is cool, pinning every core to its 800 MHz floor.
  # Clearing bit0 frees the cores to turbo; real thermal throttling (TCC, the
  # other PROCHOT source) still works. The MSR resets across suspend, so the
  # unit binds to sleep.target: ExecStart clears at boot, ExecStop re-clears on
  # every resume when sleep.target deactivates.
  boot.kernelModules = [ "msr" ];
  systemd.services.kait2en-clear-bd-prochot =
    let
      clearProchot = pkgs.writeShellScript "clear-bd-prochot" ''
        v=$(${pkgs.msr-tools}/bin/rdmsr -p0 0x1FC)
        ${pkgs.msr-tools}/bin/wrmsr -a 0x1FC $(( 0x$v & ~1 ))
      '';
    in
    {
      description = "Clear stuck BD PROCHOT (MSR_POWER_CTL 0x1FC bit0)";
      wantedBy = [
        "multi-user.target"
        "sleep.target"
      ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = clearProchot;
        ExecStop = clearProchot;
      };
    };
}
