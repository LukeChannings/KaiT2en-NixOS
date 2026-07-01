# The KaiT2en kernel: stock Linux 7.0 plus the minimal patch the out-of-tree
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
# Stock nixpkgs `linux_7_0` ships neither, so those modules fail to compile
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
{
  linux_7_0,
}:

let
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
linux_7_0.override {
  # Append, don't replace: keep nixpkgs' own structuredExtraConfig / patches.
  kernelPatches = (linux_7_0.kernelPatches or [ ]) ++ [
    {
      name = "kait2en-hid-spi-device-types";
      patch = hidSpiDeviceTypesPatch;
    }
  ];
}
