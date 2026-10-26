# Aggregate of the KaiT2en NixOS modules, imported as one. Enabling this gives
# you the `hardware.kait2en` (kernel drivers/cmdline/blacklist),
# `hardware.kait2en.firmware` (declarative Wi-Fi/Bluetooth firmware) and
# `hardware.kait2en.gpuControl` (model-exclusive GPU app) options plus the
# `services.{t2-fan-control,t2-smc-control,t2-touchbar,t2bce-audio-dsp,
# kait2en-suspend,kait2en-rtc-sync,t2-services,t2-ave,t2-touchid,t2-journal,
# t2-power-explorer,t2-power-tune,t2-zone-power,t2-force-click}` options; each
# leaves itself disabled until you set its `enable = true`. The exception is
# `services.kait2en-app-folder`, on by default under GNOME, which groups
# whichever of those GUI apps are enabled into one app-grid folder.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./kait2en-kernel
    ./brcm-firmware
    ./t2-fan-control
    ./t2-smc-control
    ./t2-touchbar
    ./t2bce-audio-dsp
    ./kait2en-suspend
    ./kait2en-rtc-sync
    ./t2-services
    ./t2-power-explorer
    ./t2-power-tune
    ./t2-zone-power
    ./t2-force-click
    ./t2-gpu-control
    ./kait2en-app-folder
  ];

  # The KaiT2en GUI apps' CSS names the bundled JetBrains Mono, which upstream
  # installs alongside the wordmark (install-apps.sh `install_app_assets`).
  config = lib.mkIf config.hardware.kait2en.enable {
    fonts.packages = [ (pkgs.callPackage ../pkgs/kait2en-branding { }) ];
  };
}
