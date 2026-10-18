# The KaiT2en kernel: the Fedora-matched base kernel plus the minimal patch the out-of-tree
# T2 HID drivers need to build.
#
# Background. KaiT2en's `hid_t2magicmouse` and `t2touchbar/t2hid` are the
# t2linux forks of the in-tree `hid-magicmouse` / `hid-apple` drivers. They
# also carry the Apple SPI-HID (BUS_SPI) and apple_bce host (BUS_HOST) code
# paths, which reference three symbols that only exist in a kernel carrying the
# t2linux `4001-asahi-trackpad.patch`:
#
#   * enum hid_type { … HID_TYPE_SPI_KEYBOARD, HID_TYPE_SPI_MOUSE }
#   * #define HID_SPI_DEVICE(ven, prod)
#
# Stock nixpkgs kernels ship neither, so those modules fail to compile
# against it (the SPI/HOST branches are dead code on a T2 Mac, but the symbols
# still have to resolve).
#
# Rather than shim the symbols into each module — or apply the *whole* t2linux
# series, whose in-tree drivers KaiT2en deliberately blacklists and replaces —
# this carries just the `include/linux/hid.h` hunk of that upstream patch: the
# kernel ABI the out-of-tree drivers compile against, nothing more.
#
# Usage: this returns a *kernel* (not a kernelPackages set). Wrap it with
# `pkgs.linuxPackagesFor` to get a kernelPackages set for
# `boot.kernelPackages`, and build the T2 modules against `kait2enKernel`
# itself (see ../../modules and ../../modules/kait2en-kernel).
#
# Config. `t2bce_ave` (in the t2bce stack) is a V4L2 mem2mem encoder and links
# against the kernel's `v4l2-mem2mem` helper (CONFIG_V4L2_MEM2MEM_DEV). That
# symbol has no prompt — it only exists when a driver selects it — and stock
# nixpkgs selects none, so modpost fails with undefined `v4l2_m2m_*`. Mirror
# upstream's apps/t2-kernel-builder/engine/build.sh: keep VIDEO_VIM2M as a
# module purely as the selecting driver.
# Kernel selection policy: match the kernel series Fedora stable currently
# ships (upstream KaiT2en targets Fedora's kernel; their modules often need
# compat fixes before a newer series works). Bump `baseKernel` below — the
# single site — when Fedora moves and upstream's modules are compatible.
# Query Fedora's current series with:
#   curl -s 'https://bodhi.fedoraproject.org/updates/?packages=kernel&status=stable&rows_per_page=1' | jq -r '.updates[0].version'
# If nixpkgs doesn't ship that exact series yet, take the nearest lower one.
# Any bump must re-check the SPI-HID ABI patch below against the new kernel's
# include/linux/hid.h (drop the patch if HID_SPI_DEVICE went in-tree; rebase
# it if the hunk drifted).
{
  pkgs,
}:

let
  baseKernel = pkgs.linux_7_2; # ← kernel bumps touch only this line

  # Content-address the patch by its own bytes, NOT as a subpath of the flake
  # source. When KaiT2en is consumed as a `path:`/git flake input, every file in
  # the repo lives under one `…-source` store path whose hash covers the WHOLE
  # tree; referencing `./patches/0001-….patch` directly embeds that whole-tree
  # path into the kernel's `kernelPatches`, so editing any unrelated file (a
  # module `.c`, even the README) moves `…-source`, changes the patch's store
  # path, and forces a full kernel rebuild. `builtins.path` with a single-file
  # `path` gives the patch a store path derived only from its own contents,
  # stable across unrelated repo edits — so the kernel is rebuilt only when the
  # patch itself changes.
  hidSpiDeviceTypesPatch = builtins.path {
    name = "kait2en-hid-add-spi-hid-device-types-and-macro.patch";
    path = ./patches/0001-hid-add-spi-hid-device-types-and-macro.patch;
  };
in
baseKernel.override {
  # Append, don't replace: keep nixpkgs' own structuredExtraConfig / patches.
  kernelPatches = (baseKernel.kernelPatches or [ ]) ++ [
    {
      name = "kait2en-hid-spi-device-types";
      patch = hidSpiDeviceTypesPatch;
    }
    {
      name = "kait2en-t2bce-ave-v4l2-mem2mem";
      patch = null;
      structuredExtraConfig = with pkgs.lib.kernel; {
        MEDIA_TEST_SUPPORT = yes;
        V4L_TEST_DRIVERS = yes;
        VIDEO_VIM2M = module; # selects V4L2_MEM2MEM_DEV for t2bce_ave
      };
    }
  ];
}
