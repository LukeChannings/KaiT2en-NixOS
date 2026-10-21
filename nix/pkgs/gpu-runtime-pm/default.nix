# amdgpu with upstream's GPU runtime PM series, built out of tree against
# `kernel` — the NixOS port of scripts/fedora/install-gpu-runtime-pm.sh.
#
# Upstream rebuilds *only* the amdgpu module from the running kernel's source
# with patches/runtime/gpu-runtime-pm/series applied (GMUX runtime PM so the
# dGPU reaches D3cold under t2-hybrid-gpu-control, 5K iMac panel support, and
# the Navi 14/Navi power-limit quirks), builds it with `M=` against the
# kernel's build tree and installs it under `updates/kait2en-gpu-runtime-pm`,
# where depmod's default `search updates built-in` lets it shadow the in-tree
# amdgpu. We do the same, so the hybrid profiles do not need a second full
# kernel build: the module is built against `kernel.dev` from `kernel.src`.
#
# Patch handling mirrors the script: entries are read from `series`;
# `patch_needed_for_kernel` skips 0001 (merged in 7.3, backported to 7.2.10+);
# each remaining patch is applied with `--forward --fuzz=3`, and one that
# already reverse-applies is treated as present. `amdgpu_trace.h`'s
# TRACE_INCLUDE_PATH is pointed at `.` as the script does, which the `M=`
# build needs.
#
# The patch dir is content-addressed on its own (builtins.path), so unrelated
# repo edits do not rebuild the module.
#
# The module is signed with kmodigest in postFixup so `aggregateModules` finds
# its `amdgpu.ko.cer` — see "Signing" in ../../kernel-module.nix.
{
  lib,
  stdenv,
  kmod,
  kmodigest,
  kernel,
}:

let
  patchDir = builtins.path {
    name = "kait2en-gpu-runtime-pm-patches";
    path = ../../../patches/runtime/gpu-runtime-pm;
  };

  series = lib.filter (entry: entry != "" && !lib.hasPrefix "#" entry) (
    lib.splitString "\n" (builtins.readFile (patchDir + "/series"))
  );

  # install-gpu-runtime-pm.sh `patch_needed_for_kernel`.
  patchNeeded =
    name:
    !(
      name == "0001-drm-amdgpu-reset-VI-ASIC-on-MacBookPro15-1.patch"
      && lib.versionAtLeast kernel.version "7.2.10"
    );

  patches = map (name: "${patchDir}/${name}") (lib.filter patchNeeded series);

  inherit (kernel) modDirVersion;
  kernelBuildDir = "${kernel.dev}/lib/modules/${modDirVersion}/build";
  amdgpuDir = "drivers/gpu/drm/amd/amdgpu";
in
stdenv.mkDerivation {
  pname = "kait2en-gpu-runtime-pm";
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

  # Only the AMD driver tree is needed (its Kbuild includes nothing outside
  # drivers/gpu/drm/amd).
  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src" --strip-components=1 --wildcards '*/drivers/gpu/drm/amd/*'
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

    trace_header=${amdgpuDir}/amdgpu_trace.h
    grep -q '^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/amd/amdgpu$' "$trace_header" || {
      echo "unexpected AMDGPU trace include path" >&2
      exit 1
    }
    sed -i 's|^#define TRACE_INCLUDE_PATH ../../drivers/gpu/drm/amd/amdgpu$|#define TRACE_INCLUDE_PATH .|' \
      "$trace_header"
    runHook postPatch
  '';

  buildPhase = ''
    runHook preBuild
    make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${amdgpuDir}" modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 ${amdgpuDir}/amdgpu.ko \
      "$out/lib/modules/${modDirVersion}/updates/kait2en-gpu-runtime-pm/amdgpu.ko"
    runHook postInstall
  '';

  # After the strip pass, which would drop the appended signature.
  postFixup = ''
    kmodigest "$out/lib/modules/${modDirVersion}/updates/kait2en-gpu-runtime-pm/amdgpu.ko"
  '';

  meta = {
    description = "amdgpu with the KaiT2en GPU runtime PM series (GMUX D3cold, 5K iMac panel)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
