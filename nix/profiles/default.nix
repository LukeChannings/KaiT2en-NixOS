# Per-device KaiT2en NixOS profiles.
#
# Unlike the modules under ../modules (which expose generic options left
# disabled until you opt in), a profile encodes the concrete configuration for
# one specific T2 Mac model: which audio DSP graph to load, and any other
# model-specific quirks. Import the one that matches your machine and it turns
# on the right pieces with the right settings.
#
# The model ids mirror upstream's dsp/profiles/<profile> tree (dsp/config/models.json):
#
#   - macbookpro16-1  → MacBookPro16,1 (audio DSP model "16_1")
#   - macbookpro16-4  → MacBookPro16,4 (audio DSP model "16_4")
#   - macbookair9-1   → MacBookAir9,1  (audio DSP model "9_1")
#
# This file is the model-agnostic baseline those profiles share — it imports
# the aggregate KaiT2en modules (../modules) and sets what every T2 Mac wants
# regardless of model. It deliberately enables nothing model-specific (no audio
# DSP — importing every model's graph at once would be contradictory), so do
# not import it directly: pick a concrete profile (e.g. ./macbookpro16-1.nix).
{
  lib,
  config,
  pkgs,
  ...
}:

{
  imports = [ ../modules ];

  services.t2-touchbar.users = lib.mkDefault [ config.system.primaryUser ];

  # The T2 bridge (05ac:8233) is a CDC-NCM link; cdc_mbim can claim the
  # interface ahead of cdc_ncm and break the bridgeOS services that t2-services
  # reaches over it.
  boot.blacklistedKernelModules = [ "cdc_mbim" ];

  # Shared bridge-link integration (NM "Apple T2 Bridge" link-local profile +
  # suspend hook runner), and the bridgeOS services upstream installs on every
  # T2 Mac: AVE (t2remote) and the Touch ID bridge for fprintd.
  services.t2-services.enable = lib.mkDefault true;
  services.t2-services.manageNetworkProfile = lib.mkDefault false;
  # According to https://discussions.apple.com/thread/7763102,
  # the T2 network bridge uses the same MAC address on all T2 Macs.
  networking.networkmanager.unmanaged = [ "mac:ac:de:48:00:11:22" ];

  systemd.network.links."10-t2-ncm" = {
    matchConfig.MACAddress = "ac:de:48:00:11:22";
    linkConfig.Name = "t2ncm";
  };

  systemd.services.t2-ncm-link = {
    description = "Bring up the T2 bridge link";
    bindsTo = [ "sys-subsystem-net-devices-t2ncm.device" ];
    after = [ "sys-subsystem-net-devices-t2ncm.device" ];
    wantedBy = [ "sys-subsystem-net-devices-t2ncm.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip link set dev t2ncm up";
    };
  };

  # linux-firmware blobs: amdgpu (Navi) on the dGPU models, plus assorted
  # platform firmware. hardware.kait2en.firmware only covers Wi-Fi/Bluetooth.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # Enable Thunderbolt management
  services.hardware.bolt.enable = lib.mkDefault true;

  # t2bce-audio-dsp's payload (per-model filter-chain graphs + UCM) loads into
  # PipeWire/WirePlumber; without PipeWire the DSP is inert and the internal
  # speakers/mics stay raw. rtkit gives PipeWire its realtime scheduling.
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };
  security.rtkit.enable = lib.mkDefault true;

  services.upower = {
    enable = lib.mkDefault true;
    criticalPowerAction = "PowerOff";
    percentageLow = 20;
    percentageCritical = 10;
    percentageAction = 5;
  };

  boot.plymouth.enable = lib.mkDefault true;
  boot.plymouth.theme = lib.mkDefault "spinner";
  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "rd.systemd.show_status=auto"
  ];
}
