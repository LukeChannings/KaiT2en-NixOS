# NixOS module for the T2 Mac audio: upstream's UCM split + `dsp/` filter chains.
#
# `t2bce` (via t2bce_audio) brings up the raw `AppleT2x<N>` sound card. Driving
# its speakers directly is unbalanced and unsafe (no crossover, no limiter), so
# this module installs upstream's host-side audio stack exactly as
# scripts/fedora/install-alsa-ucm.sh + install-dsp.sh (`make -C dsp install`)
# do, with the Fedora lifecycle's DMI pick replaced by `model`:
#
#   1. ALSA UCM: the AppleT2 use cases (modules/t2bce_audio-alsa-ucm-conf,
#      packaged with the stock tree as nix/pkgs/t2bce_audio-alsa-ucm-conf)
#      expose the raw multichannel PCM, the headphone PCM and the mic PCM as
#      the Speaker / Headphones / Mic devices. NixOS' alsa-lib reads its UCM
#      tree from the store, so `ALSA_CONFIG_UCM2` points PipeWire, WirePlumber
#      and the alsa CLI at the overlaid tree.
#   2. udev (dsp's 89-t2-dsp.rules): renames the card's ALSA id to
#      `t2-<profile>` from the DMI product name; everything below keys off it.
#   3. WirePlumber (dsp's 51-t2-dsp.conf + t2-default-output.lua): raw-mic and
#      raw-speaker rename, speaker allowed-rates, headphone priority and the
#      jack-follows-default hook. The raw speaker node is marked
#      `Audio/Sink/Internal`, and the card's `[Out] Speaker` port hidden, so
#      only the DSP sink is user-selectable.
#   4. PipeWire: the model's filter chains (`share/t2-dsp/pipewire/<model>.conf`,
#      which upstream's lifecycle `configure_dsp_pipewire` copies to
#      /etc/pipewire/pipewire.conf.d/51-t2-dsp.conf) targeting the UCM node
#      `alsa_output.hw_t2-<model>_0`. The LV2 plugins the graphs use
#      (bankstown, lsp-plugins) reach LV2_PATH via `requiredLv2Packages`.
#
# The raw speaker node is hidden, not removed: it is the DSP graph's backend,
# and reaching it directly would bypass the crossover and limiter. Headphones
# and the headset mic get no DSP.
# Switching from the earlier kekrby ACP integration leaves stale T2 entries in
# ~/.local/state/wireplumber/default-{profile,nodes,routes}; clear them once
# (install-alsa-ucm.sh `reset_wireplumber_t2_profile_state` does the same).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2bce-audio-dsp;
  pwCfg = config.services.pipewire;

  ucmConf = pkgs.callPackage ../../pkgs/t2bce_audio-alsa-ucm-conf { };
  ucmEnv.ALSA_CONFIG_UCM2 = "${ucmConf}/share/alsa/ucm2";

  # The DMI-selected graph upstream's lifecycle installs, chosen by `model`.
  pipewireGraph =
    pkgs.runCommand "t2-dsp-pipewire-${cfg.model}"
      {
        passthru.requiredLv2Packages = cfg.package.requiredLv2Packages or [ ];
      }
      ''
        install -D -m 0644 ${cfg.package}/share/t2-dsp/pipewire/${cfg.model}.conf \
          "$out/share/pipewire/pipewire.conf.d/51-t2-dsp.conf"
      '';
in
{
  imports = [
    # This module replaces the old `services.t2-apple-audio-dsp` (lemmyg tree)
    # in place; keep old configs working by aliasing the options across.
    (lib.mkRenamedOptionModule
      [ "services" "t2-apple-audio-dsp" "enable" ]
      [ "services" "t2bce-audio-dsp" "enable" ]
    )
    (lib.mkRenamedOptionModule
      [ "services" "t2-apple-audio-dsp" "model" ]
      [ "services" "t2bce-audio-dsp" "model" ]
    )
  ];

  options.services.t2bce-audio-dsp = {
    enable = lib.mkEnableOption "the T2 Mac audio UCM split and DSP filter chains (speaker crossover/limiter and mic beamforming)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../dsp/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../dsp/package.nix { }";
      description = "The t2-dsp package (upstream's `dsp/`).";
    };

    model = lib.mkOption {
      type = lib.types.enum [
        "8_1"
        "8_2"
        "9_1"
        "15_1"
        "15_2"
        "15_3"
        "15_4"
        "16_1"
        "16_2"
        "16_3"
        "16_4"
        "imac20_1"
        "imacpro1_1"
      ];
      example = "16_1";
      description = ''
        The T2 Mac model whose PipeWire DSP graph to load, matching upstream's
        `dsp/config/models.json` (`MacBookAir8,1` → `"8_1"`,
        `MacBookPro16,1` → `"16_1"`, `iMac20,1` → `"imac20_1"`, …). It must
        match the machine's DMI product name: udev names the card from DMI and
        the graph only attaches to its own model's card.

        The DSP graphs are tuned per model; selecting the wrong one drives the
        speakers with the wrong crossover/limiter and can damage them.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ cfg.package ];

    services.pipewire.configPackages = [ pipewireGraph ];
    services.pipewire.wireplumber.configPackages = [ cfg.package ];

    systemd.user.services = lib.mkIf (!pwCfg.systemWide) {
      pipewire.environment = ucmEnv;
      wireplumber.environment = ucmEnv;
    };
    systemd.services = lib.mkIf pwCfg.systemWide {
      pipewire.environment = ucmEnv;
      wireplumber.environment = ucmEnv;
    };

    # alsaucm / alsamixer use cases outside PipeWire.
    environment.variables = ucmEnv;
  };
}
