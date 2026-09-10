# A complete ALSA UCM2 tree = stock `alsa-ucm-conf` plus the KaiT2en Apple T2
# split-channel use-case profiles (super's `modules/t2bce_audio-alsa-ucm-conf`).
#
# The `t2bce_audio` driver names its card `AppleT2x<N>` where N is the speaker
# channel count (x2/x4/x6). ALSA UCM matches that card `driver` string to
# `conf.d/AppleT2x<N>/AppleT2x<N>.conf`, which pulls in `AppleT2/HiFi-x<N>.conf`
# — the profile that split-maps the raw multichannel PCM into the per-transducer
# Speaker/Mic devices the audio DSP graphs then target.
#
# Those profiles `Include` files from the stock tree (`/common/pcm/split.conf`),
# so we can't ship them standalone: this derivation copies the upstream
# `alsa-ucm-conf` ucm2 tree and overlays the AppleT2 files on top, yielding one
# self-contained tree. Point ALSA at it with `ALSA_CONFIG_UCM2` or use it to
# override `alsa-ucm-conf`. (The `t2bce-audio-dsp` NixOS module splits the card
# via the kekrby ACP profile-set instead, so it does not consume this; the tree
# is exposed for the UCM-based split.) nixpkgs' `alsa-ucm-conf` ships no AppleT2
# profile of its own,
# so there is nothing to remove first (unlike Fedora's).
{
  lib,
  stdenvNoCC,
  alsa-ucm-conf,
}:

stdenvNoCC.mkDerivation {
  pname = "t2bce_audio-alsa-ucm-conf";
  # Track the stock tree we overlay onto; the AppleT2 profiles are versioned
  # with the wider KaiT2en tree, not independently.
  version = alsa-ucm-conf.version;

  src = lib.cleanSource ../../../modules/t2bce_audio-alsa-ucm-conf;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dst="$out/share/alsa/ucm2"
    mkdir -p "$out/share/alsa"
    cp -r ${alsa-ucm-conf}/share/alsa/ucm2 "$dst"
    chmod -R u+w "$dst"

    # Overlay the Apple T2 split-channel HiFi profiles (x2/x4/x6).
    mkdir -p "$dst/AppleT2"
    cp ucm2/AppleT2/*.conf "$dst/AppleT2/"

    # Overlay the card-driver -> profile mappings UCM auto-loads by card name.
    for driver in AppleT2x2 AppleT2x4 AppleT2x6; do
      mkdir -p "$dst/conf.d/$driver"
      cp "ucm2/conf.d/$driver/$driver.conf" "$dst/conf.d/$driver/$driver.conf"
    done

    runHook postInstall
  '';

  meta = {
    description = "ALSA UCM2 tree with the KaiT2en Apple T2 split-channel profiles";
    platforms = lib.platforms.linux;
  };
}
