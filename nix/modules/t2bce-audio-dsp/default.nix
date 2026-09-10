# NixOS module for the T2 Apple audio DSP configuration.
#
# `t2bce` (via t2bce_audio) brings up the raw `Apple T2 Audio` sound card, but
# driving its speakers directly is both unbalanced and unsafe (no crossover, no
# limiter). This module layers the Asahi-style PipeWire/WirePlumber DSP filter
# chains on top, per MacBook model.
#
# ── Why this repo's integration and not upstream's ─────────────────────────
# Upstream retired the lemmyg `modules/t2-apple-audio-dsp` tree in favour of
# `modules/t2bce_audio-dsp`. We track upstream's *DSP data* (the retuned
# per-model `graph.json`/`mic.json` + FIR `.wav`s in `firs/<model>`), but NOT
# its integration glue: `scripts/fedora/install-dsp.sh` and the committed
# `wireplumber.conf`/`99-t2-audio-rename.rules` drive an ALSA-UCM split with
# live-PCI-probed `HiFi__Speaker__sink` node names and a `hw_Audio_0` graph
# target — a path that does not work here. Instead we keep the split mechanism
# that actually works on these machines: the ALSA-Card-Profile (ACP) profile-set
# from kekrby/t2-better-audio, matched by `alsa.name = "Speaker"` / `"Digital
# Mic"`. Upstream's `graph.json`s still target the ACP `…​.Speakers` node and the
# per-model `…​.BuiltinMic` node (they only differ from the old ones in tuning
# and in using position-agnostic AUX channel labels), so they drop straight into
# this integration.
#
#   1. The per-model speaker (`graph.json`) and mic (`mic.json`) DSP graphs are
#      read from the upstream `modules/t2bce_audio-dsp/firs/<model>` tree, with
#      the `/usr/share/t2-linux-audio/<model>` FIR paths rewritten to the Nix
#      store (the same `firs/<model>` dir carries the `.wav` FIRs).
#   2. The WirePlumber drop-in is *generated* here (upstream ships no per-model
#      config for this split): `node.software-dsp.rules` point `create-filter`
#      at those store graphs with `hide-parent = true`.
#   3. The LV2 plugins the graphs reference (bankstown, triforce, lsp-plugins,
#      swh) are added to WirePlumber's LV2 search path.
#
# Pick your model with `services.t2bce-audio-dsp.model`. The MacBookPro16,1 is
# model `"16_1"` — see the profiles under `nix/profiles`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2bce-audio-dsp;

  # Upstream's current DSP data tree (retuned graphs + FIRs for every model).
  audioFiles = ../../../modules/t2bce_audio-dsp;
  inherit (cfg) model;

  # The Pro models (15,x / 16,x) carry the multi-transducer arrays whose codec
  # re-mutes the raw devices out from under the DSP; the 2-channel Airs (8,x /
  # 9,x) do not, matching the per-model configs this repo shipped before.
  needsForceUnmute = lib.hasPrefix "15_" model || lib.hasPrefix "16_" model;

  # ── Raw T2 card -> named ALSA devices (Speakers / Digital Mic) ─────────────
  # t2bce brings the speakers up as ONE undifferentiated multichannel ALSA
  # device (`alsa_output.pci-….multichannel-output`). The DSP layer below,
  # however, keys off the per-transducer split the way macOS/Asahi expose it:
  # the `node.software-dsp.rules` match `alsa.name = "Speaker"` / `"Digital
  # Mic"`, and each graph's `playback.props.target.object` is the `…​.Speakers`
  # node. Without that split nothing matches and every DSP link fails ("N of N
  # PipeWire links failed to activate") — only a Dummy sink survives.
  #
  # The split comes from the ALSA-Card-Profile (ACP) layer inside PipeWire's
  # libspa-alsa loading the per-model profile-set (apple-t2x{2,4,6}.conf) +
  # mixer paths from kekrby/t2-better-audio. Stock nixpkgs PipeWire does NOT
  # ship these in its ACP mixer dir, so two things are needed:
  #
  #   1. The profile-set/path files must be present in the *running* PipeWire's
  #      `share/alsa-card-profile/mixer/` dir. `pipewirePackage` below overrides
  #      pkgs.pipewire to copy kekrby's `files/{profile-sets,paths}` into the
  #      ACP mixer source tree at build time. Without it libspa-alsa logs
  #      `profile-set 'apple-t2x6.conf' can't be accessed: No such file or
  #      directory` and only a Dummy sink survives.
  #   2. libspa-alsa reads the `ACP_PROFILE_SET` udev property per card to pick
  #      which set to load, so the udev rule below stamps it on the T2 sound
  #      card.
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

  # kekrby/t2-better-audio ships the ACP profile-sets + mixer paths that teach
  # libspa-alsa how to split the raw T2 card into the named Speaker/Digital Mic
  # devices. Stock nixpkgs PipeWire doesn't carry them, so override the package
  # to drop them into the ACP mixer source dir (`spa/plugins/alsa/mixer/`)
  # before it's built. WirePlumber must be rebuilt against the SAME PipeWire
  # (it links libpipewire), else it loads the stock one at runtime and the
  # profile-sets are missing again.
  audioProfileFiles = pkgs.fetchFromGitHub {
    owner = "kekrby";
    repo = "t2-better-audio";
    rev = "e46839a28963e2f7d364020518b9dac98236bcae";
    hash = "sha256-x7K0qa++P1e1vuCGxnsFxL1d9+nwMtZUJ6Kd9e27TFs=";
  };

  pipewirePackage = pkgs.pipewire.overrideAttrs (
    _new: old: {
      preConfigurePhases = (old.preConfigurePhases or [ ]) ++ [ "postPatchPhase" ];
      postPatchPhase = ''
        cp -r ${audioProfileFiles}/files/{profile-sets,paths} spa/plugins/alsa/mixer/
      '';
    }
  );

  # The upstream graphs reference their FIRs by the Fedora install path; the
  # same files live at this store path, so that is what the references are
  # rewritten to.
  oldPath = "/usr/share/t2-linux-audio/${model}";
  newPath = "${audioFiles}/firs/${model}";

  # The speaker / mic DSP graphs with their FIR (.wav) references repointed at
  # the Nix store. mic.json carries no .wav paths today but the rewrite is
  # harmless and keeps the two graphs symmetric.
  dspGraph = pkgs.runCommand "t2-dsp-graph-${model}.json" { } ''
    sed -e 's|${oldPath}|${newPath}|g' ${newPath}/graph.json > $out
  '';
  dspMic = pkgs.runCommand "t2-dsp-mic-${model}.json" { } ''
    sed -e 's|${oldPath}|${newPath}|g' ${newPath}/mic.json > $out
  '';

  # The generated WirePlumber drop-in: create the speaker + mic DSP filter
  # chains on the ACP-split raw nodes and hide those raw nodes behind them.
  # Upstream ships no per-model config for the ACP split (its own config drives
  # the broken UCM path), so we emit it here in the shape this repo has always
  # used.
  dspSinkConfig = ''
    # Generated by nix/modules/t2bce-audio-dsp for model ${model}.
    node.software-dsp.rules = [
        {
            matches = [
                { api.alsa.card.name = "Apple T2 Audio", alsa.name = "Speaker" }
            ]
            actions = {
                create-filter = {
                    filter-path = "${dspGraph}"
                    hide-parent = true
                }
            }
        }
        {
            matches = [
                { api.alsa.card.name = "Apple T2 Audio", alsa.name = "Digital Mic" }
            ]
            actions = {
                create-filter = {
                    filter-path = "${dspMic}"
                    hide-parent = true
                }
            }
        }
    ]

    wireplumber.profiles = {
        main = {
            node.software-dsp = required
        }
    }
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
    enable = lib.mkEnableOption "the T2 Mac audio DSP filter chains (speaker crossover/limiter and mic beamforming)";

    model = lib.mkOption {
      type = lib.types.enum [
        "8_1"
        "8_2"
        "9_1"
        "15_1"
        "15_2"
        "15_4"
        "16_1"
        "16_2"
        "16_3"
        "16_4"
      ];
      example = "16_1";
      description = ''
        The T2 MacBook model whose DSP profile to install, matching the
        `firs/<model>` dirs upstream ships (`MacBookAir8,1` → `"8_1"`,
        `MacBookPro16,1` → `"16_1"`, …).

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

    # PipeWire carrying the kekrby ACP profile-sets.
    services.pipewire.package = pipewirePackage;

    services.pipewire.wireplumber = {
      # Rebuild WirePlumber against the patched PipeWire (it links libpipewire —
      # a mismatched stock WirePlumber would load the un-patched PipeWire at
      # runtime and the profile-sets would be missing again).
      package = pkgs.wireplumber.override {
        pipewire = pipewirePackage;
      };

      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf" dspSinkConfig)
      ];

      # Hide the analog headphone-jack sink while nothing is plugged in, so the
      # output picker shows a single "…​DSP Speakers" entry instead of it plus a
      # permanently-listed (but dead) "Headphones". The apple-t2x{2,4,6} profile
      # exposes Speakers and Headphones as TWO always-present output mappings;
      # the DSP layer's `hide-parent` only suppresses the raw *Speakers* node,
      # leaving Headphones visible even with an empty jack.
      #
      # The card reports jack state as the `t2-headphones` output route's
      # `available` field ("yes" when plugged, "no"/"unknown" otherwise). This
      # script revokes read permission on the headphone sink node for every
      # non-infrastructure client whenever that route is unavailable (removing
      # it from the picker, the same mechanism WirePlumber's software-dsp
      # `hide-parent` uses) and restores it when a jack is plugged in.
      extraScripts = {
        "hide-jack-when-unplugged.lua" = ''
          clients_om = ObjectManager { Interest { type = "client" } }
          hp_om = ObjectManager {
            Interest {
              type = "node",
              Constraint { "alsa.name", "=", "Codec Output", type = "pw" },
              Constraint { "media.class", "=", "Audio/Sink", type = "pw" },
            }
          }
          devices_om = ObjectManager {
            Interest {
              type = "device",
              Constraint { "alsa.card_name", "=", "Apple T2 Audio", type = "pw" },
            }
          }

          hp_node_id = nil

          function is_infra(client)
            local p = client.properties
            return p["wireplumber.daemon"] or p["application.name"] == "pipewire"
          end

          -- Read the t2-headphones output route's availability across all T2
          -- audio devices. Returns true only when a jack is actually plugged in.
          function jack_available()
            for device in devices_om:iterate() do
              for p in device:iterate_params("EnumRoute") do
                local r = p:parse()
                if r.pod_type == "Object" and r.object_id == "EnumRoute" then
                  if r.properties.name == "t2-headphones" then
                    if r.properties.available == "yes" then
                      return true
                    end
                  end
                end
              end
            end
            return false
          end

          function apply()
            if hp_node_id == nil then return end
            local perm = jack_available() and "r-" or "-"
            for client in clients_om:iterate { type = "client" } do
              if not is_infra(client) then
                client:update_permissions { [hp_node_id] = perm }
              end
            end
          end

          hp_om:connect("object-added", function(om, node)
            hp_node_id = node["bound-id"]
            apply()
          end)
          hp_om:connect("object-removed", function(om, node) hp_node_id = nil end)
          clients_om:connect("object-added", function(om, client) apply() end)
          -- Re-evaluate on plug/unplug: the device emits params-changed for
          -- "Route" when a jack's availability flips.
          devices_om:connect("object-added", function(om, device)
            device:connect("params-changed", function(d, name)
              if name == "Route" then apply() end
            end)
          end)

          clients_om:activate()
          hp_om:activate()
          devices_om:activate()
        '';
      }
      // lib.optionalAttrs needsForceUnmute {
        # Force the raw Speaker/Mic routes to unmuted full volume so the DSP
        # always has proper input/output levels; the Pro codecs otherwise
        # re-mute them out from under the filter chain. (The 2-channel Airs do
        # not need this, matching the per-model configs this repo shipped.)
        "t2-force-unmute.lua" = builtins.readFile ./t2-force-unmute.lua;
      };

      extraConfig."99-t2-dsp-scripts" = {
        "wireplumber.components" = [
          {
            name = "hide-jack-when-unplugged.lua";
            type = "script/lua";
          }
        ]
        ++ lib.optional needsForceUnmute {
          name = "t2-force-unmute.lua";
          type = "script/lua";
        };
      };

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
