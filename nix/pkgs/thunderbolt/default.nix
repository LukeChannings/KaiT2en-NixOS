# The in-tree thunderbolt driver with upstream's thunderbolt series, built out
# of tree against `kernel` — the NixOS port of
# scripts/fedora/install-thunderbolt.sh, which replaced the retired
# `t2thunderbolt` module.
#
# Upstream rebuilds only drivers/thunderbolt from the running kernel's source
# with patches/runtime/thunderbolt/series applied (Titan Ridge RTD3 through the
# Darwin _PS0/_PS3 sequence of its root ports, runtime PM for the Ice Lake
# routers), builds it with `M=` against the kernel's build tree and installs it
# under `updates/kait2en-thunderbolt`, where depmod's default `search updates
# built-in` lets it shadow the in-tree module. Same here, like
# nix/pkgs/wireless.
#
# Mirrors the script:
#   * only drivers/thunderbolt is taken from the kernel source;
#   * `load_patch_series` + `apply_patch_if_needed`: every series entry, with
#     `--forward --fuzz=3`; one that already reverse-applies counts as present.
#   * the `is_supported_model` PCI probe (T2 bridge 106b:1801 plus a Titan
#     Ridge or Ice Lake NHI) has no Nix equivalent: the profiles enable it for
#     the models that have one.
#
# The kernel must build THUNDERBOLT as a module, or there is nothing to shadow.
#
# The patch dir is content-addressed on its own (builtins.path), so unrelated
# repo edits do not rebuild the module. Signed with kmodigest in postFixup so
# `aggregateModules` finds its `.ko.cer` — see "Signing" in
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
    name = "kait2en-thunderbolt-patches";
    path = ../../../patches/runtime/thunderbolt;
  };

  series = lib.filter (entry: entry != "" && !lib.hasPrefix "#" entry) (
    lib.splitString "\n" (builtins.readFile (patchDir + "/series"))
  );

  patches = map (name: "${patchDir}/${name}") series;

  inherit (kernel) modDirVersion;
  kernelBuildDir = "${kernel.dev}/lib/modules/${modDirVersion}/build";
  tbDir = "drivers/thunderbolt";
  installDir = "lib/modules/${modDirVersion}/updates/kait2en-thunderbolt";
in
stdenv.mkDerivation {
  pname = "kait2en-thunderbolt";
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

  # The script copies only drivers/thunderbolt out of the kernel source.
  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src" --strip-components=1 --wildcards '*/drivers/thunderbolt/*'
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
    runHook postPatch
  '';

  configurePhase = ''
    runHook preConfigure
    if [[ $(sed -n 's/^CONFIG_USB4=//p' ${kernelBuildDir}/.config) != m ]]; then
      echo "${kernel.version} does not build the thunderbolt driver (USB4) as a module" >&2
      exit 1
    fi
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${tbDir}" modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    [[ -f ${tbDir}/thunderbolt.ko ]] || { echo "thunderbolt.ko was not built" >&2; exit 1; }
    install -Dm644 ${tbDir}/thunderbolt.ko "$out/${installDir}/thunderbolt.ko"
    runHook postInstall
  '';

  # After the strip pass, which would drop the appended signature.
  postFixup = ''
    kmodigest "$out/${installDir}/thunderbolt.ko"
  '';

  meta = {
    description = "thunderbolt with the KaiT2en series (Titan Ridge and Ice Lake RTD3 on T2 Macs)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
