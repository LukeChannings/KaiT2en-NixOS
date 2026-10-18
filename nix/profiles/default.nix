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
{ lib, ... }:

{
  imports = [ ../modules ];

  # The T2 bridge (05ac:8233) is a CDC-NCM link; cdc_mbim can claim the
  # interface ahead of cdc_ncm and break the bridgeOS services that t2-services
  # reaches over it.
  boot.blacklistedKernelModules = [ "cdc_mbim" ];

  # linux-firmware blobs: amdgpu (Navi) on the dGPU models, plus assorted
  # platform firmware. hardware.kait2en.firmware only covers Wi-Fi/Bluetooth.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # t2bce-audio-dsp's payload (per-model filter-chain graphs + UCM) loads into
  # PipeWire/WirePlumber; without PipeWire the DSP is inert and the internal
  # speakers/mics stay raw. rtkit gives PipeWire its realtime scheduling.
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };
  security.rtkit.enable = lib.mkDefault true;
}
