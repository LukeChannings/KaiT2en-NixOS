# Per-device KaiT2en NixOS profiles.
#
# Unlike the modules under ../modules (which expose generic options left
# disabled until you opt in), a profile encodes the concrete configuration for
# one specific T2 Mac model: which audio DSP graph to load, and any other
# model-specific quirks. Import the one that matches your machine and it turns
# on the right pieces with the right settings.
#
# The model ids mirror upstream's t2bce_audio-dsp firs/<model> tree:
#
#   - macbookpro16-1  → MacBookPro16,1 (audio DSP model "16_1")
#   - macbookpro16-4  → MacBookPro16,4 (audio DSP model "16_4")
#   - macbookair9-1   → MacBookAir9,1  (audio DSP model "9_1")
#
# These import the aggregate KaiT2en modules (../modules) so a profile is the
# only thing you need to add to your host configuration.
{
  imports = [ ];

  # Intentionally empty: there is no "all devices" profile — importing every
  # model's audio DSP at once would be contradictory. Pick a concrete profile
  # from this directory instead (e.g. ./macbookpro16-1.nix).
}
