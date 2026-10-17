# t2-dsp: upstream's host-side Apple T2 speaker/mic DSP (dsp/), built exactly
# as `make -C dsp install` does, but into $out.
#
# `tools/build.py --datadir $out/share` generates, from dsp/profiles +
# dsp/config/models.json:
#   * share/t2-dsp/profiles/<profile>/  graphs (FIR paths relocated to $out)
#     + the XTC-side-*.wav FIRs
#   * share/t2-dsp/pipewire/<profile>.conf  the PipeWire filter-chain modules
#     for one model (upstream's lifecycle copies the DMI-matched one to
#     /etc/pipewire/pipewire.conf.d/51-t2-dsp.conf; the NixOS module selects it
#     by `services.t2bce-audio-dsp.model` instead)
#   * share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf  monitor rules (raw
#     mic rename, speaker allowed-rates, headphone priority) + the
#     t2-default-output hook, and share/wireplumber/scripts/t2-default-output.lua
#   * lib/udev/rules.d/89-t2-dsp.rules  renames the t2bce_audio card's ALSA id
#     to `t2-<profile>` from the DMI product name (/usr/bin/cat → coreutils)
#
# The Fedora lifecycle/migration helpers (integration/libexec,
# packaging/lifecycle) are not consumed. `requiredLv2Packages` is picked up by
# NixOS' pipewire/wireplumber modules for LV2_PATH (the graphs use bankstown and
# lsp-plugins; upstream dropped Triforce/SWH).
{
  lib,
  stdenvNoCC,
  python3,
  coreutils,
  bankstown-lv2,
  lsp-plugins,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "t2-dsp";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [ python3 ];

  buildPhase = ''
    runHook preBuild
    python3 tools/build.py --output build --datadir "$out/share"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/share/t2-dsp/profiles" "$out/share/t2-dsp/pipewire"
    cp -r build/profiles/. "$out/share/t2-dsp/profiles/"
    cp -r build/pipewire/. "$out/share/t2-dsp/pipewire/"
    install -m 0644 build/models.json "$out/share/t2-dsp/models.json"

    install -D -m 0644 build/51-t2-dsp.conf \
      "$out/share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf"
    install -D -m 0644 integration/wireplumber/t2-default-output.lua \
      "$out/share/wireplumber/scripts/t2-default-output.lua"

    install -D -m 0644 build/89-t2-dsp.rules "$out/lib/udev/rules.d/89-t2-dsp.rules"
    substituteInPlace "$out/lib/udev/rules.d/89-t2-dsp.rules" \
      --replace-fail '/usr/bin/cat' '${coreutils}/bin/cat'

    runHook postInstall
  '';

  passthru.requiredLv2Packages = [
    bankstown-lv2
    lsp-plugins
  ];

  meta = {
    description = "PipeWire/WirePlumber DSP graphs for the internal speakers and mics of Apple T2 Macs";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
})
