# KaiT2en profile for the MacBookAir9,1 (T2, 2020 MacBook Air).
#
# Turns on everything upstream's installer sets up on this machine: the
# out-of-tree T2 kernel drivers, Wi-Fi/Bluetooth firmware, the suspend/resume
# and RTC fixes, the T2 bridge services (AVE, Touch ID), the fan/SMC/power/
# Force Click apps and this model's audio DSP profile ("9_1"). Import it from
# your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookair9-1 ];
#
# Unlike the 16" MacBook Pro profiles this omits services.t2-touchbar (no Touch
# Bar) and hardware.kait2en.gpuControl (integrated Ice Lake graphics only).
#
# Notes:
#   * hardware.kait2en.firmware is unfree and builds inside a VM — set
#     nixpkgs.config.allowUnfree = true (or allowlist "brcm-firmware") and have
#     KVM available, or set hardware.kait2en.firmware.enable = false if you copy
#     the Broadcom blobs in by hand instead.
#   * Touch ID: log into macOS once after a T2 power loss so the SEP unlocks,
#     then bind your finger with `fprintd-enroll` (or set
#     services.t2-touchid.bindUser = "<you>"; to bind automatically).
{ ... }:

{
  imports = [ ./default.nix ];

  hardware.kait2en = {
    enable = true;
    firmware.enable = true;
    # Generic installer branch: amdgpu.aspm=1 (harmless without an AMD GPU;
    # upstream adds it on every model but the MacBookPro16,1), pcie_aspm=force
    # + powersave.
    amdgpuAspm = true;
    pcieAspm = "force";
  };

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
    model = "9_1";
  };
}
