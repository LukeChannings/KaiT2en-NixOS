# i915 and drm_display_helper with upstream's i915 series, built out of tree
# against `kernel` — the NixOS port of scripts/fedora/install-i915.sh.
#
# Upstream rebuilds drm_display_helper (the Apple panel PSR quirk) and i915
# (the Apple TCON PSR handshake, restoring the gmux brightness on T2
# MacBook Pros) from the running kernel's source with
# patches/runtime/i915/series applied, builds them with `M=` against the
# kernel's build tree and installs them under `updates/kait2en-i915`, where
# depmod's default `search updates built-in` lets them shadow the in-tree
# modules. Same here, like nix/pkgs/gpu-runtime-pm.
#
# Mirrors the script:
#   * `load_patch_series` + `apply_patch_if_needed`: every series entry, with
#     `--forward --fuzz=3`; one that already reverse-applies counts as present.
#   * the KUnit tests are taken out of the i915 Makefile (`obj-n`), which an
#     external build cannot link;
#   * `rewrite_trace_path`: the four trace headers' TRACE_INCLUDE_PATH is
#     pointed at its own directory, which `-I$(src)` resolves in an `M=`
#     build; any other value is a hard error, as upstream.
#   * the `is_supported_model` probe (a MacBook or iMac with an Intel GPU at
#     00:02.0) has no Nix equivalent: the profiles enable it for the models
#     that have one.
#
# The patch dir is content-addressed on its own (builtins.path), so unrelated
# repo edits do not rebuild the modules. Signed with kmodigest in postFixup so
# `aggregateModules` finds each `.ko.cer` — see "Signing" in
# ../../kernel-module.nix.
{
  lib,
  stdenv,
  kmod,
  kmodigest,
  kernel,
}:

let
  patchDir = builtins.path {
    name = "kait2en-i915-patches";
    path = ../../../patches/runtime/i915;
  };

  series = lib.filter (entry: entry != "" && !lib.hasPrefix "#" entry) (
    lib.splitString "\n" (builtins.readFile (patchDir + "/series"))
  );

  patches = map (name: "${patchDir}/${name}") series;

  inherit (kernel) modDirVersion;
  kernelBuildDir = "${kernel.dev}/lib/modules/${modDirVersion}/build";
  i915Dir = "drivers/gpu/drm/i915";
  displayHelperDir = "drivers/gpu/drm/display";
  installDir = "lib/modules/${modDirVersion}/updates/kait2en-i915";
in
stdenv.mkDerivation {
  pname = "kait2en-i915";
  version = "${kernel.version}";

  inherit (kernel) src;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    kmod
    kmodigest
  ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  # The script copies the whole source tree; the DRM tree is what the two
  # builds read, plus the one header i915 includes from outside it
  # (gt/intel_rps.c: ../../../platform/x86/intel_ips.h).
  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src" --strip-components=1 --wildcards \
      '*/drivers/gpu/drm/*' \
      '*/drivers/platform/x86/intel_ips.h'
    runHook postUnpack
  '';

  patchPhase = ''
    runHook prePatch
    flags=(-p1 --batch --fuzz=3 --no-backup-if-mismatch)
    for p in ${lib.escapeShellArgs patches}; do
      if patch "''${flags[@]}" --dry-run --forward < "$p" > /dev/null 2>&1; then
        echo "applying $(basename "$p")"
        patch "''${flags[@]}" --forward < "$p"
      elif patch "''${flags[@]}" --dry-run --reverse < "$p" > /dev/null 2>&1; then
        echo "$(basename "$p") is already present"
      else
        echo "patch does not apply to ${kernel.version}: $(basename "$p")" >&2
        exit 1
      fi
    done

    sed -i 's|^obj-\$(CONFIG_DRM_I915_KUNIT_TEST) += display/tests/$|obj-n += display/tests/|' \
      ${i915Dir}/Makefile

    rewrite_trace_path() {
      local header=$1 upstream=$2 local_path=$3
      grep -q -e "^#define TRACE_INCLUDE_PATH $upstream\$" "$header" || {
        echo "unexpected trace include path in ''${header##*/}" >&2
        exit 1
      }
      sed -i "s|^#define TRACE_INCLUDE_PATH $upstream\$|#define TRACE_INCLUDE_PATH $local_path|" "$header"
    }
    rewrite_trace_path ${i915Dir}/i915_trace.h ../../drivers/gpu/drm/i915 .
    rewrite_trace_path ${i915Dir}/intel_uncore_trace.h ../../drivers/gpu/drm/i915 .
    rewrite_trace_path ${i915Dir}/display/intel_display_trace.h \
      ../../drivers/gpu/drm/i915/display display
    rewrite_trace_path ${i915Dir}/gvt/trace.h ../../drivers/gpu/drm/i915/gvt gvt
    runHook postPatch
  '';

  configurePhase = ''
    runHook preConfigure
    kernel_config() {
      sed -n "s/^CONFIG_$1=//p" ${kernelBuildDir}/.config
    }
    for option in DRM_I915 DRM_DISPLAY_HELPER; do
      if [[ $(kernel_config $option) != m ]]; then
        echo "${kernel.version} does not build $option as a module" >&2
        exit 1
      fi
    done
    runHook postConfigure
  '';

  # The Apple panel quirk lives in drm_display_helper, the PSR handshake and
  # the gmux brightness restore in i915.
  buildPhase = ''
    runHook preBuild
    make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${displayHelperDir}" modules
    make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${i915Dir}" modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for module in ${displayHelperDir}/drm_display_helper.ko ${i915Dir}/i915.ko; do
      [[ -f $module ]] || { echo "''${module##*/} was not built" >&2; exit 1; }
      install -Dm644 "$module" "$out/${installDir}/''${module##*/}"
    done
    runHook postInstall
  '';

  # After the strip pass, which would drop the appended signature.
  postFixup = ''
    find "$out/${installDir}" -name '*.ko' -print0 | xargs -0 -r -n1 kmodigest
  '';

  meta = {
    description = "i915 and drm_display_helper with the KaiT2en series (Apple panel PSR, gmux brightness restore)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
