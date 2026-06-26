# KaiT2en profile for the MacBookAir9,1 (T2, 2020 MacBook Air).
#
# Turns on everything applicable to this machine: the out-of-tree T2 kernel
# drivers, Wi-Fi/Bluetooth firmware, the suspend/resume fixes, the fan and SMC
# GUIs, and this model's audio DSP profile ("9_1", which ships no force-unmute
# Lua). Import it from your host config:
#
#   imports = [ inputs.kait2en.nixosProfiles.macbookair9-1 ];
#
# Unlike the 16" MacBook Pro profiles this omits:
#   * hardware.kait2en.forceIgd — the Air has a single (integrated) GPU.
#   * services.react-drm — the Air has no Touch Bar.
#
# Notes:
#   * hardware.kait2en.firmware is unfree and builds inside a VM — set
#     nixpkgs.config.allowUnfree = true (or allowlist "brcm-firmware") and have
#     KVM available, or set hardware.kait2en.firmware.enable = false if you copy
#     the Broadcom blobs in by hand instead.
#   * The SMC charge-limit slider needs your user in the video group; add it
#     with services.t2-smc-control.users = [ "<you>" ];
{
  imports = [ ../modules ];

  hardware.kait2en = {
    enable = true;
    firmware.enable = true;
  };

  services.kait2en-suspend.enable = true;
  services.t2-fan-control.enable = true;
  services.t2-smc-control.enable = true;

  services.t2-apple-audio-dsp = {
    enable = true;
    model = "9_1";
  };
}
