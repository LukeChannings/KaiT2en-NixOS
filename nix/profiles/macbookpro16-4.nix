# KaiT2en profile for the MacBookPro16,4 (T2, 2019 16" MacBook Pro, Radeon Pro 5600M).
#
# Turns on everything upstream's installer sets up on this machine: the
# out-of-tree T2 kernel drivers, Wi-Fi/Bluetooth firmware, the suspend/resume
# and RTC fixes, the T2 bridge services (AVE, Touch ID), the Touch Bar daemon,
# the fan/SMC/power/Force Click apps, hybrid graphics (the gpu-runtime-pm
# amdgpu + t2-hybrid-gpu-control) and this model's audio DSP profile
# ("16_4"). Import it from your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookpro16-4 ];
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
{ pkgs, ... }:

{
  imports = [ ../modules ];

  hardware.kait2en = {
    enable = true;
    firmware.enable = true;
    # Generic installer branch: amdgpu.aspm=1, pcie_aspm=force + powersave.
    amdgpuAspm = true;
    pcieAspm = "force";
    # install-apps.sh: t2-hybrid-gpu-control on this model, on top of the
    # gpu-runtime-pm amdgpu (GMUX runtime PM).
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

  # t2-journal has no system integration — just ship the CLI.
  environment.systemPackages = [ (pkgs.callPackage ../../t2-services/t2-journal/package.nix { }) ];

  services.t2bce-audio-dsp = {
    enable = true;
    model = "16_4";
  };
}
