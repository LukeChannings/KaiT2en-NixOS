# NixOS module for the KaiT2en kernel layer: build + load the out-of-tree T2
# drivers, set the kernel command line, and blacklist the conflicting in-tree
# Apple drivers.
#
# On Fedora this is done imperatively by scripts/fedora:
#   * install-dkms-modules.sh  — DKMS-build t2bce/t2smc/t2bdrm/t2touchbar/…
#   * install-kernel-args.sh   — grubby --args for IOMMU, ACPI _OSI, deep
#     sleep, initcall_blacklist and module_blacklist (the conflicting drivers)
#   * rebuild-initramfs.sh      — dracut --add-drivers for early loading
#
# Here it is all declarative. The out-of-tree modules are built against the
# running kernel (`config.boot.kernelPackages.kernel`) via the repo's
# ../../../modules builder — the same thing `self.lib.<system>.kernelModulesFor`
# exposes — and wired into boot.extraModulePackages.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.kait2en;

  # The KaiT2en kernel: the Fedora-matched base kernel + the SPI-HID ABI patch the out-of-tree T2
  # HID drivers (hid_t2magicmouse, t2touchbar/t2hid) compile against. Stock
  # nixpkgs kernels lack the SPI HID `enum hid_type` members and HID_SPI_DEVICE()
  # those drivers reference, so building them against an unpatched kernel
  # fails. See ../../pkgs/kernel.
  #
  # Applied directly (not via callPackage) so the result keeps the kernel's own
  # chainable `.override` — callPackage would wrap it in makeOverridable and
  # shadow that with an override taking only the base kernel, breaking the
  # `pkgs.linuxPackagesFor kait2enKernel` below (NixOS overrides the kernel
  # with `{ features, kernelPatches, randstructSeed }`).
  kait2enKernel = import ../../pkgs/kernel { inherit pkgs; };

  # Build every KaiT2en out-of-tree module against the configured kernel. This
  # is exactly what the flake's `lib.<system>.kernelModulesFor kernel` does;
  # done here directly so the module is usable without threading the flake's
  # `self` through specialArgs. It tracks `boot.kernelPackages.kernel`, which
  # this module defaults to the patched KaiT2en kernel below.
  builtModules = pkgs.callPackage ../../../modules {
    kernel = config.boot.kernelPackages.kernel;
  };

  # `callPackage` decorates its result with override/overrideDerivation; keep
  # only the real derivations for boot.extraModulePackages.
  kernelModulePackages = lib.filter lib.isDerivation (lib.attrValues builtModules);
in
{
  options.hardware.kait2en = {
    enable = lib.mkEnableOption "KaiT2en T2 Mac kernel drivers, command-line and module blacklist";

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackagesFor kait2enKernel;
      defaultText = lib.literalExpression "pkgs.linuxPackagesFor (the patched KaiT2en kernel)";
      description = ''
        The kernelPackages set the T2 Mac boots and the out-of-tree modules
        build against. Defaults to {option}`boot.kernelPackages` built from the
        patched KaiT2en kernel (the Fedora-matched base kernel plus the SPI-HID ABI patch the
        `hid_t2magicmouse` and `t2touchbar` drivers require). Override only if
        you carry that patch in your own kernel.
      '';
    };

    modulePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = kernelModulePackages;
      defaultText = lib.literalExpression "all KaiT2en out-of-tree modules built against config.boot.kernelPackages.kernel";
      description = ''
        The out-of-tree KaiT2en module packages to add to
        {option}`boot.extraModulePackages`. Defaults to the whole set built
        against the running kernel.
      '';
    };

    loadModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "t2smc"
        # The BCE stack split into four cross-dependent modules upstream. Module
        # softdeps enforce ordering (audio/vhci `pre: t2bce_core`, core
        # `post: t2bce_vhci`), but list them in dependency order anyway.
        "t2bce_dma"
        "t2bce_core"
        "t2bce_vhci"
        "t2bce_audio"
        "t2bdrm"
        "t2hid"
        "t2touchbar_bl"
        "t2touchbar_kbd"
        "t2mfi_fastcharge"
        "t2gmux"
        "t2thunderbolt"
        "t2smp"
        "t2sbs"
        "hid_t2magicmouse"
        # The T2 internal trackpad moved from hid_t2magicmouse to
        # t2_precision_trackpad; the actuator gives it Force Click haptics.
        "t2_trackpad_actuator"
        "t2_precision_trackpad"
      ];
      description = ''
        Loadable module names (not package names) to load at boot. Note these
        differ from the package names: the `t2touchbar` package builds `t2hid`,
        `t2touchbar_bl` and `t2touchbar_kbd`, and the `t2bce` package builds the
        split modules `t2bce_dma`, `t2bce_core`, `t2bce_vhci`, `t2bce_audio`
        and `t2bce_ave`.

        `t2bce_ave` is not loaded here: upstream loads it only from the AVE
        service unit (`ExecStartPre=modprobe t2bce_ave`), which
        {option}`services.t2-ave` mirrors.

        The Touch Bar display's USB configuration (`bConfigurationValue` of
        `05ac:8302`) is selected in userspace by the T2 Touch Bar daemon's
        attach service; enable {option}`services.t2-touchbar` for it.

        The out-of-tree `apfs` driver was dropped (upstream deleted
        `modules/apfs`). NixOS users who must mount the macOS APFS volumes can
        add nixpkgs' own `config.boot.kernelPackages.apfs` to
        {option}`boot.extraModulePackages` instead; like any filesystem driver
        it is then autoloaded on mount, not force-loaded here.
      '';
    };

    initrdModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "t2bce_dma"
        "t2bce_core"
        "t2bce_vhci"
        "t2hid"
        "t2smc"
        "t2sbs"
      ];
      description = ''
        Modules to load from the initramfs (early), mirroring upstream's
        steady-state `EARLY_MODULES` in scripts/fedora/rebuild-initramfs.sh
        (`t2bce_dma t2bce_core t2bce_vhci t2hid t2smc t2sbs`): the BCE +
        keyboard essentials, `t2smc` so its SMC-backed RTC sets the wall clock
        early, and `t2sbs` right after it so BAT0 already carries
        `charge_control_end_threshold` when udev/UPower first see it.

        `hid_t2magicmouse` left this list upstream: it no longer drives the
        internal trackpad (t2_precision_trackpad does, at normal boot).
      '';
    };

    blacklistedModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "acpi_tad"
        "applesmc"
        "macsmc"
        "hid_apple"
        "hid_appletb_bl"
        "hid_appletb_kbd"
        "hid_magicmouse"
        "appletbdrm"
        "apple_bce"
        "apple_mfi_fastcharge"
        "apple_gmux"
        # Replaced by the out-of-tree t2sbs Smart Battery driver.
        "sbs"
      ];
      description = ''
        Conflicting in-tree / upstream drivers to blacklist, matching the
        `module_blacklist=` kernel argument the Fedora installer sets. The
        KaiT2en out-of-tree drivers replace these.

        Note `thunderbolt` is no longer blacklisted: upstream reworked
        `t2thunderbolt` so it no longer conflicts with the in-tree driver (the
        Fedora installer's BLACKLIST_MODULES dropped it too).
      '';
    };

    amdgpuAspm = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add `amdgpu.aspm=1`. The Fedora installer now adds it on every model
        except the MacBookPro16,1, whose Navi 14 drops off the PCIe bus under
        load with forced ASPM. Upstream decides by DMI product name, which Nix
        eval cannot read, so this defaults to the generic branch and the
        MacBookPro16,1 profile turns it off.
      '';
    };

    pcieAspm = lib.mkOption {
      type = lib.types.enum [
        "force"
        "policy"
        "firmware"
      ];
      default = "force";
      description = ''
        PCIe ASPM handling, mirroring the installer's DMI-conditional args:

        - `"force"` — `pcie_aspm=force pcie_aspm.policy=powersave` (the
          generic branch).
        - `"policy"` — only `pcie_aspm.policy=powersave`; iMacs/iMac Pro, whose
          Ethernet controllers do not survive forced ASPM.
        - `"firmware"` — neither; the MacBookPro16,1, leaving its Navi 14 link
          to the firmware and amdgpu.

        Set per model by the profiles.
      '';
    };

    acpiOsiOverride = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add the legacy `acpi_osi=!Darwin` and `acpi_osi="Windows 2012"`
        overrides. Upstream's installer now strips every `acpi_osi` argument
        unconditionally (they break Thunderbolt hotplug on Titan Ridge / Ice
        Lake and are obsolete elsewhere), so this is off; it is kept only as an
        opt-in escape hatch.
      '';
    };

    # NOTE: the old `forceIgd` option (which added `t2gmux.force_igd=1`) was
    # removed when upstream dropped the incomplete boot-time IGD probe from
    # t2gmux (super commit "gmux: remove incomplete T2linux patch to probe igd
    # on boot"). The module no longer has a `force_igd` parameter, so passing
    # that kernel arg would make t2gmux fail to load. Define it as a removed
    # option so existing configs get a clear assertion instead of a silent
    # boot-time module-load failure.
    forceIgd = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      visible = false;
      description = ''
        Removed: t2gmux no longer carries the `force_igd` boot-time IGD probe
        (dropped upstream as incomplete), so there is nothing for this to set.
      '';
    };

    gpuRuntimePm = {
      enable = lib.mkEnableOption ''
        upstream's GPU runtime PM amdgpu (scripts/fedora/install-gpu-runtime-pm.sh):
        an out-of-tree amdgpu carrying patches/runtime/gpu-runtime-pm, which
        shadows the in-tree module and is soft-dependent on t2gmux. Upstream
        installs it on the MacBookPro15,1 / 16,1 / 16,4 (GMUX runtime PM, so
        the dGPU reaches D3cold under t2-hybrid-gpu-control) and the
        iMac20,1 / 20,2 (5K panel)'';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/gpu-runtime-pm {
          kernel = config.boot.kernelPackages.kernel;
        };
        defaultText = lib.literalExpression "the patched amdgpu built against config.boot.kernelPackages.kernel";
        description = "The patched amdgpu module package (see nix/pkgs/gpu-runtime-pm).";
      };
    };

    extraKernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra kernel command-line parameters appended to the KaiT2en defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.forceIgd == null;
        message = ''
          hardware.kait2en.forceIgd has been removed: t2gmux no longer has a
          `force_igd` parameter (the incomplete boot-time IGD probe was dropped
          upstream). Passing `t2gmux.force_igd=1` would make the module fail to
          load. Remove this option from your configuration.
        '';
      }
    ];

    # Boot the patched KaiT2en kernel so the out-of-tree modules build and load
    # against a kernel that actually exports the SPI-HID ABI. mkDefault lets a
    # host still override `boot.kernelPackages` if it must.
    boot.kernelPackages = lib.mkDefault cfg.kernelPackages;

    boot.extraModulePackages =
      cfg.modulePackages ++ lib.optional cfg.gpuRuntimePm.enable cfg.gpuRuntimePm.package;

    # install-gpu-runtime-pm.sh's kait2en-gpu-runtime-pm.conf: GMUX must
    # provide the power callbacks before AMDGPU probes.
    boot.extraModprobeConfig = lib.mkIf cfg.gpuRuntimePm.enable ''
      softdep amdgpu pre: t2gmux
    '';

    boot.kernelModules = cfg.loadModules;
    boot.initrd.kernelModules = cfg.initrdModules;

    # NixOS' blacklist writes modprobe.d entries and also keeps them out of the
    # initramfs — a superset of the upstream `module_blacklist=` cmdline arg.
    boot.blacklistedKernelModules = cfg.blacklistedModules;

    boot.kernelParams = [
      "i915.enable_guc=2"
      "intel_iommu=on"
      "iommu=pt"
      # pm_async=off was dropped upstream ("kernel-args: remove pm_async=off")
      # once t2bce fixed async PM; pci=noaer was dropped as well.
      "brcmfmac.p2pon=0"
      "pcie_ports=compat"
      "mem_sleep_default=deep"
      "initcall_blacklist=cmos_init,magicmouse_driver_init"
    ]
    ++ lib.optional (cfg.pcieAspm == "force") "pcie_aspm=force"
    ++ lib.optional (cfg.pcieAspm != "firmware") "pcie_aspm.policy=powersave"
    ++ lib.optionals cfg.acpiOsiOverride [
      "acpi_osi=!Darwin"
      # The space is kept together by the kernel's command-line quote
      # handling; NixOS does not quote params, so the quotes are literal here.
      ''acpi_osi="Windows 2012"''
    ]
    ++ lib.optional cfg.amdgpuAspm "amdgpu.aspm=1"
    ++ cfg.extraKernelParams;
  };
}
