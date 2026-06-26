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
in
{
  t2bce = mkSimple {
    pname = "t2bce";
    version = "0.041";
    meta.description = "Apple T2 BCE (Buffer Copy Engine) driver — VHCI + audio";
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
    version = "0.1";
    meta.description = "Apple T2 GMUX (graphics multiplexer) driver";
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
    meta.description = "Apple T2 Touch Bar HID, backlight and keyboard drivers";
  };

  t2thunderbolt = mkSimple {
    pname = "t2thunderbolt";
    version = "0.1";
    meta.description = "Thunderbolt driver with Apple T2 NHI fixes";
  };

  # The out-of-tree Apple File System (read/write) driver. This is what the
  # nixos-hardware linux-t2 kernel pulls in via the 8001/8002 "Add-APFS-driver"
  # patches; carried here as a normal DKMS module so a stock kernel can mount
  # the macOS APFS volumes that must stay installed (see PLAN.md).
  #
  # Its Makefile shells out to ./genver.sh (a `PRE_BUILD` in dkms.conf) to write
  # version.h before the kbuild; that script is `#!/bin/sh`, so patch its
  # shebang for the Nix sandbox. Build is otherwise the plain `make` default.
  apfs = mkSimple {
    pname = "apfs";
    version = "0.3.20";
    extraPostPatch = "patchShebangs genver.sh";
    meta.description = "Apple File System (APFS) read/write kernel module for T2 Macs";
  };
}
