# NixOS module for the KaiT2en kernel layer: build + load the out-of-tree T2
# drivers, set the kernel command line, and blacklist the conflicting in-tree
# Apple drivers.
#
# On Fedora this is done imperatively by scripts/fedora:
#   * install-dkms-modules.sh  — DKMS-build apple-t2-bridge/t2smc/t2bdrm/t2touchbar/…
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
        # The bridge stack. The vhci and audio drivers bind to devices the
        # bridge creates (an auxiliary device, the audio PCI function), so
        # they autoload; listed in dependency order anyway.
        "apple-t2-bridge"
        "apple-t2-vhci-hcd"
        "snd-apple-t2"
        "t2bdrm"
        "t2hid"
        "t2touchbar_bl"
        "t2touchbar_kbd"
        "t2mfi_fastcharge"
        "t2gmux"
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
        `t2touchbar_bl` and `t2touchbar_kbd`, and the `apple-t2-bridge` package
        builds `apple-t2-bridge`, `apple-t2-vhci-hcd`, `snd-apple-t2`,
        `t2-ave` and `t2-sidecar`.

        `t2-ave` and `t2-sidecar` are not loaded here: upstream loads them
        from the AVE service unit (`ExecStartPre=modprobe t2-ave`, `-t2-sidecar`),
        which {option}`services.t2-ave` mirrors. `t2-sidecar` is a USB driver
        and also autoloads by modalias when `apple-t2-vhci-hcd` exposes the
        Sidecar device.

        `t2thunderbolt` is gone: upstream retired it for the patched in-tree
        driver, {option}`hardware.kait2en.thunderbolt`.

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
        "apple-t2-bridge"
        "apple-t2-vhci-hcd"
        "t2hid"
        "t2smc"
        "t2sbs"
      ];
      description = ''
        Modules to load from the initramfs (early), mirroring upstream's
        steady-state `EARLY_MODULES` in scripts/fedora/rebuild-initramfs.sh
        (`apple-t2-bridge apple-t2-vhci-hcd t2hid t2smc t2sbs`): the bridge +
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

        Note `thunderbolt` is not blacklisted: upstream retired the
        `t2thunderbolt` replacement for a patched in-tree driver
        ({option}`hardware.kait2en.thunderbolt`).
      '';
    };

    amdgpuAspm = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add `amdgpu.aspm=1`. The Fedora installer adds it on every model
        (it dropped its MacBookPro16,1 exception, c5760b1). Kept as an option
        so a machine can still opt out.
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
        - `"firmware"` — neither, leaving ASPM to the firmware. No model uses
          it since upstream dropped the MacBookPro16,1 exception (c5760b1).

        Set per model by the profiles.
      '';
    };

    pciePortsCompat = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Add `pcie_ports=compat`. Upstream's installer now strips it everywhere
        (the Thunderbolt runtime PM, {option}`hardware.kait2en.thunderbolt`,
        needs the PCIe port services) except on the iMacPro1,1, which hangs in
        the SMP bring-up on resume from S3 without it. Upstream decides by DMI
        product name, which Nix eval cannot read, so this follows the generic
        branch; an iMacPro1,1 sets it.
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
        iMac20,1 / 20,2 and iMacPro1,1 (5K panel)'';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/gpu-runtime-pm {
          kernel = config.boot.kernelPackages.kernel;
        };
        defaultText = lib.literalExpression "the patched amdgpu built against config.boot.kernelPackages.kernel";
        description = "The patched amdgpu module package (see nix/pkgs/gpu-runtime-pm).";
      };
    };

    wireless = {
      enable = lib.mkEnableOption ''
        upstream's patched Broadcom wireless drivers (scripts/fedora/install-wireless.sh):
        out-of-tree brcmfmac, hci_uart, hci_bcm4377 and btbcm carrying
        patches/runtime/wireless, which shadow the in-tree modules. Upstream
        installs them on every Mac with Broadcom WLAN or Bluetooth: every T2
        Mac. Among other fixes they add the AWDL interface that
        {option}`services.t2-drop` (AirDrop) needs'';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/wireless {
          kernel = config.boot.kernelPackages.kernel;
        };
        defaultText = lib.literalExpression "the patched Broadcom drivers built against config.boot.kernelPackages.kernel";
        description = "The patched Broadcom wireless module package (see nix/pkgs/wireless).";
      };
    };

    thunderbolt = {
      enable = lib.mkEnableOption ''
        upstream's patched thunderbolt driver (scripts/fedora/install-thunderbolt.sh):
        the in-tree thunderbolt module rebuilt with patches/runtime/thunderbolt,
        which shadows the stock one and gives the Titan Ridge and Ice Lake
        controllers of T2 Macs runtime D3. It replaced the retired
        `t2thunderbolt` module. Upstream installs it on T2 Macs with a Titan
        Ridge (8086:15e8/15eb) or Ice Lake (8086:8a0d/8a17) NHI'';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/thunderbolt {
          kernel = config.boot.kernelPackages.kernel;
        };
        defaultText = lib.literalExpression "the patched thunderbolt built against config.boot.kernelPackages.kernel";
        description = "The patched thunderbolt module package (see nix/pkgs/thunderbolt).";
      };
    };

    i915 = {
      enable = lib.mkEnableOption ''
        upstream's patched Intel graphics drivers (scripts/fedora/install-i915.sh):
        i915 and drm_display_helper rebuilt with patches/runtime/i915, which
        shadow the in-tree modules (PSR on Apple panels, restoring the gmux
        brightness on T2 MacBook Pros). Upstream installs them on MacBooks and
        iMacs with an Intel GPU at 00:02.0'';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/i915 {
          kernel = config.boot.kernelPackages.kernel;
        };
        defaultText = lib.literalExpression "the patched i915 built against config.boot.kernelPackages.kernel";
        description = "The patched i915 module package (see nix/pkgs/i915).";
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
      cfg.modulePackages
      ++ lib.optional cfg.gpuRuntimePm.enable cfg.gpuRuntimePm.package
      ++ lib.optional cfg.wireless.enable cfg.wireless.package
      ++ lib.optional cfg.thunderbolt.enable cfg.thunderbolt.package
      ++ lib.optional cfg.i915.enable cfg.i915.package;

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

    # install-kernel-args.sh ADD_ARGS, minus its DMI-conditional entries,
    # which are the options below.
    boot.kernelParams = [
      "i915.enable_guc=2"
      "intel_iommu=on"
      "iommu=pt"
      # ACPI denies the OS AER and pcie_ports=native would force it; with it
      # off, resume is no longer held up by a blocked embedded controller
      # (upstream 8ca2fb3, back again since d0f2e9e).
      "pci=noaer"
      "mem_sleep_default=deep"
      "initcall_blacklist=cmos_init,magicmouse_driver_init"
    ]
    # Upstream's REMOVE_ARGS now strips pm_async=off: with the runtime
    # wireless series the BCM4377 and BCM4364 pass S3 with asynchronous
    # suspend. The stock brcmfmac still refuses to suspend async (b53cacd),
    # so a system without hardware.kait2en.wireless keeps the old argument.
    # (brcmfmac.p2pon=0 is gone for good, upstream a3b86a8: p2pon defaults
    # off, and the series fixed the "hp2p" capability match that turned it
    # on.)
    ++ lib.optional (!cfg.wireless.enable) "pm_async=off"
    ++ lib.optional cfg.pciePortsCompat "pcie_ports=compat"
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
