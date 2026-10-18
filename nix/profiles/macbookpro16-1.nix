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
{ ... }:

{
  imports = [ ../modules ];

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
}
