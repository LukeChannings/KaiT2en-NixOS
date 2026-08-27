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
  # plumbing needed (this is option (1) from SYNC-PLAN.md). Source is just the
  # four `t2bce_*` subdirectories, laid out as siblings.
  t2bceSubdirs = [
    "t2bce_dma"
    "t2bce_core"
    "t2bce_vhci"
    "t2bce_audio"
  ];
  t2bceSrc = lib.cleanSourceWith {
    name = "t2bce-source";
    src = ./.;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (toString ./. + "/") (toString path);
        top = lib.head (lib.splitString "/" rel);
      in
      lib.elem top t2bceSubdirs;
  };
in
{
  # The whole BCE stack (core + dma + vhci + audio), built in dependency order
  # as one derivation. Version tracks t2bce_core's dkms.conf (0.06).
  t2bce = buildKernelModule {
    pname = "t2bce";
    version = "0.06";
    src = t2bceSrc;
    buildSubdirs = t2bceSubdirs;
    meta.description = "Apple T2 BCE stack (core + dma + vhci + audio)";
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
    meta.description = "HID driver for Apple Magic Mouse and T2 trackpads";
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

  # NOTE: the out-of-tree `apfs` (linux-apfs-rw) driver was dropped when
  # upstream (super/main) deleted `modules/apfs`. NixOS users who must mount
  # the macOS APFS volumes can use nixpkgs' own
  # `config.boot.kernelPackages.apfs` (a.k.a. `linuxKernel.packages.*.apfs`)
  # via `boot.extraModulePackages`. See README / module docs.
}
