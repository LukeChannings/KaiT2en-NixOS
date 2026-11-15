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

  # The plain modules: a single `.c` compiled by their own Makefile's default
  # target. Source is the module subdirectory.
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

  # The out-of-tree AVE and Sidecar drivers, which upstream keeps with their
  # userspace in t2-services/t2-ave and builds into the bridge package.
  t2AveKernelSrc = lib.cleanSource ../t2-services/t2-ave/kernel;
in
{
  # The T2 bridge stack, which replaced the t2bce_* split (dma, core, vhci,
  # audio) upstream: `apple-t2-bridge` (the Bridge Controller and its DMA
  # queues), `apple-t2-vhci-hcd` (the virtual USB host for keyboard, trackpad
  # and Touch Bar) and `snd-apple-t2` (audio), laid out like the kernel tree
  # and built by one top-level Kbuild. Like install-dkms-modules.sh
  # `copy_module_source`, `t2-ave` (the AVE encoder client) and `t2-sidecar`
  # (the USB driver for the Sidecar encoder the vhci exposes) are staged into
  # the tree as `t2-ave/` and `t2-sidecar/`, where the Kbuild picks them up so
  # all five share one Module.symvers. Version tracks
  # modules/apple-t2-bridge/dkms.conf.
  apple-t2-bridge = buildKernelModule {
    pname = "apple-t2-bridge";
    version = "0.1";
    src = lib.cleanSource ./apple-t2-bridge;
    extraPostPatch = ''
      for sub in t2-ave t2-sidecar; do
        cp -r ${t2AveKernelSrc}/"$sub" "$sub"
        chmod -R u+w "$sub"
      done
    '';
    meta.description = "Apple T2 bridge stack (bridge + vhci + audio + ave + sidecar)";
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
    version = "0.9";
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

  # NOTE: `t2thunderbolt` was retired upstream: the patched in-tree
  # thunderbolt driver (patches/runtime/thunderbolt, scripts/fedora/
  # install-thunderbolt.sh) replaces it -- see nix/pkgs/thunderbolt and
  # hardware.kait2en.thunderbolt.
  #
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
