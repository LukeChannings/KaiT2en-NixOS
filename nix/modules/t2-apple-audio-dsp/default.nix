# NixOS module for the T2 Apple audio DSP configuration (../../../modules/t2-apple-audio-dsp).
#
# `t2bce` brings up the raw `Apple T2 Audio` sound card, but driving its
# speakers directly is both unbalanced and unsafe (no crossover, no limiter).
# This module layers the Asahi-style PipeWire/WirePlumber DSP filter chains from
# lemmyg/t2-apple-audio-dsp on top, per MacBook model:
#
#   1. The per-model speaker (`graph.json`) and mic (`mic.json`) DSP graphs are
#      copied out of this repo's vendored tree, with the upstream
#      `/usr/share/t2-linux-audio/<model>` FIR paths rewritten to the Nix store
#      (the vendored `firs/<model>` directory already carries the `.wav` FIRs).
#   2. The WirePlumber drop-in (`51-t2-dsp.conf`) is rewritten to point its
#      `node.software-dsp` rules at those store graphs (and, on the 16,x models,
#      the force-unmute Lua script) and shipped as a WirePlumber config package.
#   3. The LV2 plugins the graphs reference (bankstown, triforce, lsp-plugins,
#      swh) are added to WirePlumber's LV2 search path.
#
# The set of supported models and their layout mirrors upstream exactly; pick
# yours with `services.t2-apple-audio-dsp.model`. This machine is a MacBookPro16,1,
# i.e. model `"16_1"` — see the profiles under `nix/profiles`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-apple-audio-dsp;

  audioFiles = ../../../modules/t2-apple-audio-dsp;
  model = cfg.model;

  # ── Raw T2 card -> named ALSA devices (Speakers / Digital Mic) ─────────────
  # t2bce brings the speakers up as ONE undifferentiated multichannel ALSA
  # device (`alsa_output.pci-….multichannel-output`). The DSP layer below,
  # however, keys off the per-transducer split the way macOS/Asahi expose it:
  # the `node.software-dsp.rules` in 51-t2-dsp.conf match `alsa.name =
  # "Speaker"` / `"Digital Mic"`, and each graph's `playback.props.target.object`
  # is the `…​.Speakers` node. Without that split nothing matches and every DSP
  # link fails ("N of N PipeWire links failed to activate") — only a Dummy sink
  # survives.
  #
  # The split comes from the ALSA-Card-Profile (ACP) layer inside PipeWire's
  # libspa-alsa loading the per-model profile-set (apple-t2x{2,4,6}.conf) +
  # mixer paths, originally from kekrby/t2-better-audio. PipeWire now ships
  # those files in its stock ACP mixer dir, so nothing needs to be fetched or
  # patched — ACP just has to be told which set to use. libspa-alsa reads the
  # `ACP_PROFILE_SET` udev property per card, so the only missing piece is the
  # udev rule that stamps it on the T2 sound card.
  #
  # The rule matches the T2 audio PCI device (Apple vendor 0x106b, device
  # 0x1803) and derives N from the AppleT2x<N> card id in /proc/asound/cards
  # (x6 on the MacBookPro16,1's six-transducer array), selecting
  # apple-t2x<N>.conf.
  t2AudioUdevRules = pkgs.writeTextDir "lib/udev/rules.d/91-t2-audio-profile.rules" ''
    SUBSYSTEM!="sound", GOTO="t2_audio_end"
    ACTION!="change", GOTO="t2_audio_end"
    KERNEL!="card*", GOTO="t2_audio_end"

    SUBSYSTEMS=="pci", ATTRS{vendor}=="0x106b", ATTRS{device}=="0x1803", PROGRAM="${pkgs.gnused}/bin/sed -n 's/.*AppleT2x\([0-9]\).*/\1/p' /proc/asound/cards", ENV{ACP_PROFILE_SET}="apple-t2x%c.conf"

    LABEL="t2_audio_end"
  '';

  # The vendored FIRs/graphs/Lua for this model already live at this store path,
  # so it is what the upstream `/usr/share/t2-linux-audio/<model>` references are
  # rewritten to.
  oldPath = "/usr/share/t2-linux-audio/${model}";
  newPath = "${audioFiles}/firs/${model}";

  configFile = "${audioFiles}/config/${model}/51-t2-dsp.conf";
  luaPath = "${newPath}/t2-force-unmute.lua";

  # The speaker / mic DSP graphs with their FIR (.wav) references repointed at
  # the Nix store. mic.json carries no .wav paths today but the rewrite is
  # harmless and keeps the two graphs symmetric.
  dspGraph = pkgs.runCommand "t2-dsp-graph-${model}.json" { } ''
    sed -e 's|${oldPath}|${newPath}|g' ${newPath}/graph.json > $out
  '';
  dspMic = pkgs.runCommand "t2-dsp-mic-${model}.json" { } ''
    sed -e 's|${oldPath}|${newPath}|g' ${newPath}/mic.json > $out
  '';

  # The WirePlumber drop-in, with every upstream `/usr/share` path rewritten to
  # the store: the speaker graph, the mic graph and (16,x only) the force-unmute
  # Lua. The 9,1 conf has no Lua/components block, so that substitution is a
  # no-op there.
  dspSinkConfig = pkgs.runCommand "51-t2-dsp-${model}.conf" { } ''
    sed \
      -e 's|${oldPath}/graph.json|${dspGraph}|g' \
      -e 's|${oldPath}/mic.json|${dspMic}|g' \
      -e 's|${oldPath}/t2-force-unmute.lua|${luaPath}|g' \
      ${configFile} > $out
  '';
in
{
  options.services.t2-apple-audio-dsp = {
    enable = lib.mkEnableOption "the T2 Mac audio DSP filter chains (speaker crossover/limiter and mic beamforming)";

    model = lib.mkOption {
      type = lib.types.enum [
        "16_1"
        "16_4"
        "9_1"
      ];
      example = "16_1";
      description = ''
        The T2 MacBook model whose DSP profile to install. One of:

        - `"16_1"` — MacBookPro16,1
        - `"16_4"` — MacBookPro16,4
        - `"9_1"`  — MacBookAir9,1

        The DSP graphs are tuned per model; selecting the wrong one drives the
        speakers with the wrong crossover/limiter and can damage them.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The DSP graphs use the builtin convolver plus several LV2 plugins; the
    # convolver lives in pipewire itself, the rest are pulled in below.
    environment.systemPackages = [ pkgs.ladspaPlugins ];

    # Split the raw T2 card into the named Speakers / Digital Mic / …​ ALSA
    # devices the DSP layer targets (see the ACP profile-set note above).
    services.udev.packages = [ t2AudioUdevRules ];

    services.pipewire.wireplumber = {
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf" (
          builtins.readFile "${dspSinkConfig}"
        ))
      ];

      extraLv2Packages = with pkgs; [
        bankstown-lv2
        swh_lv2
        lsp-plugins
        # The triforce beamformer is what the mic graph uses; on releases before
        # 26.05 its meta.platforms omits linux, so widen it to allow eval.
        (triforce-lv2.overrideAttrs (_old: {
          meta.platforms = lib.platforms.linux;
        }))
      ];
    };
  };
}
