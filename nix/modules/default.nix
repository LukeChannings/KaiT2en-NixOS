# Aggregate of the KaiT2en NixOS modules, imported as one. Enabling this gives
# you the `hardware.kait2en` (kernel drivers/cmdline/blacklist) option, the
# `hardware.kait2en.firmware` (declarative Wi-Fi/Bluetooth firmware) option plus
# the `services.t2-fan-control`, `services.t2-smc-control`, `services.react-drm`,
# `services.t2-apple-audio-dsp` and `services.kait2en-suspend` options; each leaves
# itself disabled until you set its `enable = true`.
{
  imports = [
    ./kait2en-kernel
    ./brcm-firmware
    ./t2-fan-control
    ./t2-smc-control
    ./react-drm
    ./t2-apple-audio-dsp
    ./kait2en-suspend
  ];
}
