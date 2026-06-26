# t2-apple-audio-dsp

PipeWire/WirePlumber **DSP filter-chain** configuration for the speakers and
built-in microphone exposed by the T2 audio device, driven through `t2bce`'s
audio path.

`t2bce` brings up the sound *card*, but on its own the raw `Apple T2 Audio`
device drives the speakers with no gain correction, no crossover, no bass
extension and no protective limiting — playing into it at volume can damage the
speakers. This config layers an Asahi-style DSP graph on top: per-model FIR
convolution (tweeter/woofer crossover), virtual-bass, loudness compensation and
a lookahead limiter for the speakers, and a beamforming + high-pass chain for
the built-in mic. The raw device is hidden so applications only ever see the
DSP-processed sink/source.

## What the pieces are

The vendored tree is organised by **model id** — `16_1` (MacBookPro16,1),
`16_4` (MacBookPro16,4) and `9_1` (MacBookAir9,1):

- `firs/<model>/graph.json` — the speaker DSP filter graph (LV2 + builtin
  convolver nodes) referencing that model's FIR `.wav` files.
- `firs/<model>/mic.json` — the built-in microphone DSP graph (triforce
  beamformer + high-pass).
- `firs/<model>/*.wav` — the measured FIR impulse responses per sample rate
  (tweeters/woofers for the 16,x models; full-range per-rate FIRs for 9,1).
- `firs/<model>/t2-force-unmute.lua` — a WirePlumber script that keeps the raw
  `Apple T2 Audio` route unmuted at full volume so the DSP gets clean levels
  (present for the 16,x models).
- `config/<model>/51-t2-dsp.conf` — the WirePlumber drop-in that wires the
  `node.software-dsp` rules to the graphs above and hides the parent devices.

## Provenance

Vendored from
[lemmyg/t2-apple-audio-dsp](https://github.com/lemmyg/t2-apple-audio-dsp)
(MIT, see `LICENSE`), itself based on the Asahi Linux userspace audio
configuration (`asahi-audio`) and the chadmed `bankstown-lv2` / `triforce-lv2`
plugins. Upstream installs the FIRs/graphs/Lua under
`/usr/share/t2-linux-audio/<model>` and the WirePlumber drop-in under
`/etc/wireplumber/wireplumber.conf.d`; the `services.t2-apple-audio-dsp` NixOS
module instead rewrites the graph paths to the Nix store and ships everything as
WirePlumber config/Lua/LV2 packages.

> **Warning:** misconfigured DSP settings in userspace can permanently damage
> the speakers. Only enable a profile that matches your actual model.

## Installation

- **NixOS:** enable `services.t2-apple-audio-dsp` and pick your model with
  `services.t2-apple-audio-dsp.model` (`"16_1"`, `"16_4"` or `"9_1"`). See
  `nix/modules/t2-apple-audio-dsp`. It installs the DSP graphs (paths rewritten to
  the Nix store), the WirePlumber drop-in, the force-unmute Lua and the required
  LV2 plugins (`bankstown-lv2`, `triforce-lv2`, `lsp-plugins`, `swh_lv2`).
- **Fedora / other:** run upstream's `install.sh` from a checkout of
  [t2-apple-audio-dsp](https://github.com/lemmyg/t2-apple-audio-dsp), or install
  its `.deb`. It copies `config/<model>/*-dsp.conf` into
  `/etc/wireplumber/wireplumber.conf.d/` and `firs/<model>/*` into
  `/usr/share/t2-linux-audio/<model>/`.
