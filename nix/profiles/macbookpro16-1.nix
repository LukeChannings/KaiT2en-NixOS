# KaiT2en profile for the MacBookPro16,1 (T2, 2019 16" MacBook Pro).
#
# Turns on everything applicable to this machine: the out-of-tree T2 kernel
# drivers, Wi-Fi/Bluetooth firmware, the suspend/resume fixes, the internal T2
# debug-interface handling, the Touch Bar runtime, the fan and SMC GUIs, and
# this model's audio DSP profile ("16_1"). Import it from your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookpro16-1 ];
#
# Notes:
#   * hardware.kait2en.firmware is unfree and builds inside a VM — set
#     nixpkgs.config.allowUnfree = true (or allowlist "brcm-firmware") and have
#     KVM available, or set hardware.kait2en.firmware.enable = false if you copy
#     the Broadcom blobs in by hand instead.
#   * The Touch Bar (react-drm) and the SMC charge-limit slider need your user
#     in the video/input groups; add it with
#     services.react-drm.users = [ "<you>" ];
#     services.t2-smc-control.users = [ "<you>" ];
{
  imports = [ ../modules ];

  hardware.kait2en = {
    enable = true;
    firmware.enable = true;
    # Radeon Pro 5300M/5500M dGPU — one of the models the installer enables
    # AMDGPU ASPM on (amdgpu.aspm=1).
    amdgpuAspm = true;
    # Titan Ridge Thunderbolt (8086:15e8/15eb): upstream removes the acpi_osi
    # overrides here (they break hotplug on this Thunderbolt generation).
    acpiOsiOverride = false;
  };

  services.kait2en-suspend.enable = true;
  services.t2-ncm.enable = true;
  services.react-drm.enable = true;
  services.t2-fan-control.enable = true;
  services.t2-smc-control.enable = true;

  services.t2-apple-audio-dsp = {
    enable = true;
    model = "16_1";
  };
}
