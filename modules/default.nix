# Every KaiT2en out-of-tree kernel module, built against a given `kernel`.
#
# These are normally installed via DKMS on Fedora (see ../scripts/fedora and
# each module's dkms.conf). Here they are plain `buildKernelModule`
# derivations: callable as `pkgs.linuxPackages.callPackage`-style with a
# `kernel`, and consumable from NixOS through `boot.extraModulePackages`.
{
  lib,
  callPackage,
  kernel,
}:

let
  buildKernelModule = args: callPackage ./../nix/kernel-module.nix { inherit kernel; } args;

  # The plain modules: a single `.c` (or `t2bce`'s multi-object tree) compiled
  # by their own Makefile's default target. Source is the module subdirectory.
  mkSimple =
    {
      pname,
      version,
      dir ? pname,
      meta ? { },
      extraPostPatch ? "",
    }:
    buildKernelModule {
      inherit
        pname
        version
        meta
        extraPostPatch
        ;
      src = lib.cleanSource (./. + "/${dir}");
    };

  # The BCE stack was split upstream into four cross-dependent modules
  # (super: t2bce → t2bce_core 0.06 + t2bce_dma + t2bce_vhci + t2bce_audio).
  # `t2bce_core` links against `t2bce_dma`'s exported symbols; `t2bce_vhci` and
  # `t2bce_audio` link against `t2bce_core`'s. Their Makefiles find each
  # sibling's headers and `Module.symvers` by relative path (`../t2bce_dma`,
  # `../t2bce_core`), so we build all four in a single derivation, in
  # dependency order, inside one unpacked tree — no KBUILD_EXTRA_SYMBOLS
  # plumbing needed. Source is the four `t2bce_*` module subdirectories, laid
  # out as siblings, plus `t2bce_ave`.
  #
  # Upstream's `t2bce_stack` DKMS package builds `t2bce_ave` (the T2 Apple
  # Video Encoder client) as a fifth member, staging it from
  # `t2-services/t2-ave/kernel/t2bce_ave` into the stack tree (see
  # scripts/fedora/install-dkms-modules.sh `copy_module_source`). Its Makefile
  # prefers a sibling `../t2bce_core`, so we stage it the same way: copied in
  # next to the other four in postPatch, built last.
  t2bceModuleSubdirs = [
    "t2bce_dma"
    "t2bce_core"
    "t2bce_vhci"
    "t2bce_audio"
  ];
  t2bceSubdirs = t2bceModuleSubdirs ++ [ "t2bce_ave" ];
  t2bceAveSrc = lib.cleanSource ../t2-services/t2-ave/kernel/t2bce_ave;
  t2bceSrc = lib.cleanSourceWith {
    name = "t2bce-source";
    src = ./.;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (toString ./. + "/") (toString path);
        top = lib.head (lib.splitString "/" rel);
      in
      lib.elem top t2bceModuleSubdirs;
  };
in
{
  # The whole BCE stack (dma + core + vhci + audio + ave), built in dependency
  # order as one derivation. Version tracks modules/t2bce_stack/dkms.conf.
  t2bce = buildKernelModule {
    pname = "t2bce";
    version = "0.01";
    src = t2bceSrc;
    buildSubdirs = t2bceSubdirs;
    extraPostPatch = ''
      cp -r ${t2bceAveSrc} t2bce_ave
      chmod -R u+w t2bce_ave
    '';
    meta.description = "Apple T2 BCE stack (dma + core + vhci + audio + ave)";
  };

  t2smc = mkSimple {
    pname = "t2smc";
    version = "0.1";
    meta.description = "Apple T2 SMC driver (fan + battery charge limit)";
  };

  t2bdrm = mkSimple {
    pname = "t2bdrm";
    version = "0.1";
    meta.description = "Apple T2 Touch Bar DRM driver";
  };

  t2gmux = mkSimple {
    pname = "t2gmux";
    version = "0.8";
    meta.description = "Apple T2 GMUX (graphics multiplexer) driver";
  };

  t2smp = mkSimple {
    pname = "t2smp";
    version = "0.1";
    meta.description = "Apple T2 SMP/CPU-offlining companion driver";
  };

  t2mfi_fastcharge = mkSimple {
    pname = "t2mfi_fastcharge";
    version = "0.1";
    meta.description = "Apple MFi fast charge driver for T2 Macs";
  };

  hid_t2magicmouse = mkSimple {
    pname = "hid_t2magicmouse";
    version = "0.1";
    meta.description = "HID driver for Apple Magic Mouse/Trackpad (external; T2 internal trackpads moved to t2_precision_trackpad)";
  };

  # The T2 internal-trackpad driver. Upstream moved the internal trackpads off
  # hid_t2magicmouse (now external Magic Mouse/Trackpad only) onto this one.
  t2_precision_trackpad = mkSimple {
    pname = "t2_precision_trackpad";
    version = "0.01";
    meta.description = "Apple T2 internal trackpad HID driver (Force Touch/Click)";
  };

  # Haptic actuator for the T2 trackpad. t2_precision_trackpad weak-links it
  # (symbol_get), the Touch Bar daemon drives its `play` parameter.
  t2_trackpad_actuator = mkSimple {
    pname = "t2_trackpad_actuator";
    version = "0.01";
    meta.description = "Apple T2 trackpad haptic actuator driver";
  };

  # Replaces the in-tree ACPI `sbs` driver (blacklisted) with a fixed Smart
  # Battery driver that exposes the SMC charge-limit threshold on BAT0.
  t2sbs = mkSimple {
    pname = "t2sbs";
    version = "0.1";
    meta.description = "Apple T2 ACPI Smart Battery driver";
  };

  t2touchbar = mkSimple {
    pname = "t2touchbar";
    version = "0.1";
    meta.description = "Apple T2 Touch Bar HID, USB config selector, backlight and keyboard drivers";
  };

  t2thunderbolt = mkSimple {
    pname = "t2thunderbolt";
    version = "0.6";
    meta.description = "Thunderbolt driver with Apple T2 NHI fixes";
  };

  # NOTE: `modules/t2sep` is deliberately not packaged: upstream lists it under
  # LEGACY_MODULES (install-dkms-modules.sh removes it; AUTOINSTALL="no").
  # Touch ID moved to the userspace t2-touchid service over the T2 bridge link.
  #
  # NOTE: the out-of-tree `apfs` (linux-apfs-rw) driver was dropped when
  # upstream (super/main) deleted `modules/apfs`. NixOS users who must mount
  # the macOS APFS volumes can use nixpkgs' own
  # `config.boot.kernelPackages.apfs` (a.k.a. `linuxKernel.packages.*.apfs`)
  # via `boot.extraModulePackages`. See README / module docs.
}
