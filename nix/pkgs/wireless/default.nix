# brcmfmac and the Broadcom Bluetooth drivers with upstream's wireless series,
# built out of tree against `kernel` — the NixOS port of
# scripts/fedora/install-wireless.sh.
#
# Upstream rebuilds only the Broadcom drivers from the running kernel's source
# with patches/runtime/wireless/series applied (BCM4364 TX beamforming off,
# Bluetooth ACL priority, a 200 ms power-save timeout, whole-word firmware
# capability matching, host-side AP 4-way handshake, the AWDL interface that
# t2-drop's AirDrop needs, LE advertising-report fixes, the strict duplicate
# filter quirk, ARP/ND offload off while awake), builds them with `M=` against
# the kernel's build tree and installs them under `updates/kait2en-wireless`,
# where depmod's default `search updates built-in` lets them shadow the
# in-tree modules. Same here, like nix/pkgs/gpu-runtime-pm.
#
# Mirrors the script:
#   * `select_modules`: brcmutil and brcmfmac (+ its wcc/cyw/bca vendor
#     modules) when the kernel builds BRCMFMAC as a module, hci_uart (UART
#     Bluetooth of the BCM4355/BCM4364 Macs) and hci_bcm4377 (PCIe Bluetooth)
#     likewise, and btbcm whenever a Bluetooth driver is replaced: both link to
#     it. A kernel with BT_BCM built in cannot take the patched drivers (hard
#     error); one without BT_BCM gets it built here (the series makes
#     BT_HCIBCM4377 select it). Decided from the kernel's own .config at build
#     time, as upstream does.
#   * `BRCMFMAC_MAKE_ARGS` (upstream a104fa6): neither Fedora's kernel nor
#     nixpkgs' sets CONFIG_BRCMDBG, so brcmfmac ships without `brcmf_dbg()`
#     output -- which the AWDL series leans on, and AWDL can only be debugged
#     on hardware. Building with it turns on brcmutil's debug-only exports
#     (`brcmu_dbg_hex_dump`), so brcmutil has to be rebuilt the same way and
#     brcmfmac linked against its Module.symvers.
#   * `load_patch_series` + `apply_patch_if_needed`: every series entry, with
#     `--forward --fuzz=3`; one that already reverse-applies counts as present.
#   * the `has_broadcom_wireless` DMI/PCI probe has no Nix equivalent: every
#     T2 Mac has Broadcom WLAN, so the profiles enable it unconditionally.
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
    name = "kait2en-wireless-patches";
    path = ../../../patches/runtime/wireless;
  };

  series = lib.filter (entry: entry != "" && !lib.hasPrefix "#" entry) (
    lib.splitString "\n" (builtins.readFile (patchDir + "/series"))
  );

  patches = map (name: "${patchDir}/${name}") series;

  inherit (kernel) modDirVersion;
  kernelBuildDir = "${kernel.dev}/lib/modules/${modDirVersion}/build";
  brcmfmacDir = "drivers/net/wireless/broadcom/brcm80211/brcmfmac";
  brcmutilDir = "drivers/net/wireless/broadcom/brcm80211/brcmutil";
  bluetoothDir = "drivers/bluetooth";
  # install-wireless.sh BRCMFMAC_MAKE_ARGS.
  brcmfmacMakeArgs = [
    "CONFIG_BRCMDBG=y"
    "KCPPFLAGS=-DDEBUG -DCONFIG_BRCMDBG=1"
  ];
  installDir = "lib/modules/${modDirVersion}/updates/kait2en-wireless";
in
stdenv.mkDerivation {
  pname = "kait2en-wireless";
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

  # Only the trees the script copies out of the kernel source: brcmfmac,
  # brcmutil, the brcm80211 headers they include, and drivers/bluetooth.
  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src" --strip-components=1 --wildcards \
      '*/drivers/net/wireless/broadcom/brcm80211/brcmfmac/*' \
      '*/drivers/net/wireless/broadcom/brcm80211/brcmutil/*' \
      '*/drivers/net/wireless/broadcom/brcm80211/include/*' \
      '*/drivers/bluetooth/*'
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

  # install-wireless.sh `select_modules`, against the kernel's own .config.
  configurePhase = ''
    runHook preConfigure
    kernel_config() {
      sed -n "s/^CONFIG_$1=//p" ${kernelBuildDir}/.config
    }

    modules=()
    bluetoothMakeArgs=()
    buildBrcmfmac=0
    buildBluetooth=0
    if [[ $(kernel_config BRCMFMAC) == m ]]; then
      buildBrcmfmac=1
      modules+=(
        ${brcmutilDir}/brcmutil.ko
        ${brcmfmacDir}/brcmfmac.ko
        ${brcmfmacDir}/wcc/brcmfmac-wcc.ko
        ${brcmfmacDir}/cyw/brcmfmac-cyw.ko
        ${brcmfmacDir}/bca/brcmfmac-bca.ko
      )
    fi
    [[ $(kernel_config BT_HCIUART) == m ]] && modules+=(${bluetoothDir}/hci_uart.ko)
    [[ $(kernel_config BT_HCIBCM4377) == m ]] && modules+=(${bluetoothDir}/hci_bcm4377.ko)
    if [[ " ''${modules[*]} " == *" ${bluetoothDir}/"* ]]; then
      buildBluetooth=1
      case $(kernel_config BT_BCM) in
        m) ;;
        y)
          echo "btbcm is built into ${kernel.version}, the patched Bluetooth drivers cannot link to it" >&2
          exit 1
          ;;
        *) bluetoothMakeArgs=(CONFIG_BT_BCM=m KCPPFLAGS=-DCONFIG_BT_BCM_MODULE=1) ;;
      esac
      modules+=(${bluetoothDir}/btbcm.ko)
    fi
    if (( ''${#modules[@]} == 0 )); then
      echo "${kernel.version} builds none of the Broadcom wireless drivers as modules" >&2
      exit 1
    fi
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    if (( buildBrcmfmac )); then
      make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${brcmutilDir}" \
        ${lib.escapeShellArgs brcmfmacMakeArgs} modules
      make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${brcmfmacDir}" \
        KBUILD_EXTRA_SYMBOLS="$PWD/${brcmutilDir}/Module.symvers" \
        ${lib.escapeShellArgs brcmfmacMakeArgs} modules
    fi
    if (( buildBluetooth )); then
      make -j"$NIX_BUILD_CORES" -C ${kernelBuildDir} M="$PWD/${bluetoothDir}" \
        "''${bluetoothMakeArgs[@]}" modules
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for module in "''${modules[@]}"; do
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
    description = "brcmfmac and Broadcom Bluetooth with the KaiT2en wireless series (AWDL, LE scanning, power save)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
