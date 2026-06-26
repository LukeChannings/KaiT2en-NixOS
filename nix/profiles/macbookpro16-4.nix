# KaiT2en profile for the MacBookPro16,4 (T2, 2019 16" MacBook Pro, alt board).
#
# Turns on everything applicable to this machine: the out-of-tree T2 kernel
# drivers (with the dual-GPU `force_igd` quirk), Wi-Fi/Bluetooth firmware, the
# suspend/resume fixes, the Touch Bar runtime, the fan and SMC GUIs, and this
# model's audio DSP profile ("16_4"). Import it from your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookpro16-4 ];
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
    # MacBookPro16,4 is a dual-GPU machine; force the integrated GPU.
    forceIgd = true;
    firmware.enable = true;
  };

  services.kait2en-suspend.enable = true;
  services.react-drm.enable = true;
  services.t2-fan-control.enable = true;
  services.t2-smc-control.enable = true;

  services.t2-apple-audio-dsp = {
    enable = true;
    model = "16_4";
  };
}
