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

  # The KaiT2en kernel: stock 7.0 + the SPI-HID ABI patch the out-of-tree T2
  # HID drivers (hid_t2magicmouse, t2touchbar/t2hid) compile against. Stock
  # `linux_7_0` lacks the SPI HID `enum hid_type` members and HID_SPI_DEVICE()
  # those drivers reference, so building them against an unpatched kernel
  # fails. See ../../pkgs/kernel.
  #
  # Applied directly (not via callPackage) so the result keeps the kernel's own
  # chainable `.override` — callPackage would wrap it in makeOverridable and
  # shadow that with an override taking only `linux_7_0`, breaking the
  # `pkgs.linuxPackagesFor kait2enKernel` below (NixOS overrides the kernel
  # with `{ features, kernelPatches, randstructSeed }`).
  kait2enKernel = import ../../pkgs/kernel { inherit (pkgs) linux_7_0; };

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
      defaultText = lib.literalExpression "pkgs.linuxPackagesFor (the patched KaiT2en 7.0 kernel)";
      description = ''
        The kernelPackages set the T2 Mac boots and the out-of-tree modules
        build against. Defaults to {option}`boot.kernelPackages` built from the
        patched KaiT2en kernel (stock Linux 7.0 plus the SPI-HID ABI patch the
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
        "t2bce"
        "t2bdrm"
        "t2hid"
        "t2touchbar_bl"
        "t2touchbar_kbd"
        "t2mfi_fastcharge"
        "t2gmux"
        "t2thunderbolt"
        "hid_t2magicmouse"
      ];
      description = ''
        Loadable module names (not package names) to load at boot. Note these
        differ from the package names: the `t2touchbar` package builds `t2hid`,
        `t2touchbar_bl` and `t2touchbar_kbd`.

        The `apfs` driver (package name `linux-apfs-rw`) is intentionally not
        listed: like any filesystem driver it is autoloaded by the kernel when
        an APFS volume is mounted, so it only needs to be *available* (shipped
        via {option}`hardware.kait2en.modulePackages` + depmod), not
        force-loaded at boot.
      '';
    };

    initrdModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "t2smc"
        "t2bce"
        "t2bdrm"
        "t2hid"
        "t2touchbar_bl"
        "t2touchbar_kbd"
        "t2mfi_fastcharge"
        "t2gmux"
        "t2thunderbolt"
      ];
      description = ''
        Modules to load from the initramfs (early), mirroring the upstream
        `dracut --add-drivers` list in rebuild-initramfs.sh. Needed for the
        drivers that must bind before the root device / display come up.
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
        "thunderbolt"
        "apple_bce"
        "apple_mfi_fastcharge"
        "apple_gmux"
      ];
      description = ''
        Conflicting in-tree / upstream drivers to blacklist, matching the
        `module_blacklist=` kernel argument the Fedora installer sets. The
        KaiT2en out-of-tree drivers replace these.
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

    boot.extraModulePackages = cfg.modulePackages;

    boot.kernelModules = cfg.loadModules;
    boot.initrd.kernelModules = cfg.initrdModules;

    # NixOS' blacklist writes modprobe.d entries and also keeps them out of the
    # initramfs — a superset of the upstream `module_blacklist=` cmdline arg.
    boot.blacklistedKernelModules = cfg.blacklistedModules;

    boot.kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
      "pm_async=off"
      "acpi_osi=!Darwin"
      # The space is kept together by the kernel's command-line quote
      # handling; NixOS does not quote params, so the quotes are literal here.
      ''acpi_osi="Windows 2012"''
      "pcie_ports=native"
      "mem_sleep_default=deep"
      "initcall_blacklist=cmos_init,magicmouse_driver_init"
    ]
    ++ cfg.extraKernelParams;
  };
}
