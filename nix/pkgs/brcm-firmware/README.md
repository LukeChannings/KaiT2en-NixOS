# brcm-firmware

Automatic, declarative Broadcom Wi-Fi and Bluetooth firmware for T2 Macs.

T2 Macs need the Broadcom firmware blobs that ship inside macOS. On Fedora these
are copied out of an installed macOS by hand (see the firmware howto in
`howto/`). This package is the **NixOS** alternative: it extracts the same blobs
without an installed macOS.

## How it works

1. `fetchmacos.nix` runs OpenCore's `macrecovery` to download a macOS recovery
   **BaseSystem** image for the chosen version, then converts the DMG to a raw
   image with `dmg2img`. This is a fixed-output derivation (the only step with
   network access).
2. `default.nix` mounts that image inside a throwaway Linux VM
   (`vmTools.runInLinuxVM` — needed for the loop + `hfsplus` mounts) and runs the
   patched Asahi installer scripts (`get-bluetooth` / `get-wifi`, built by
   `get-firmware.nix` with `get-firmware-standalone.patch`) over
   `/usr/share/firmware` to collect the `brcm` blobs.
3. The result is `$out/lib/firmware/brcm/*`, ready for `hardware.firmware`.

## Provenance

Ported from [`nixos-hardware`'s `apple/t2`
brcm-firmware](https://github.com/NixOS/nixos-hardware/tree/master/apple/t2/pkgs/brcm-firmware).
`macrecovery` is from [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)
(BSD-3); the firmware scripts are from the
[Asahi installer](https://github.com/AsahiLinux/asahi-installer) (MIT). The
extracted firmware itself is Apple's and **unfree**.

## Usage

Enable the NixOS module:

```nix
hardware.kait2en.firmware = {
  enable = true;
  version = "sonoma"; # or "tahoe" / "ventura" / "monterey"
};
```

or use the package directly through the flake overlay
(`pkgs.kait2en.brcm-firmware`, or `pkgs.kait2en.brcm-firmwareFor "tahoe"`).

## Constraints

- The firmware derivation is **unfree** — set
  `nixpkgs.config.allowUnfree = true` (or allowlist `brcm-firmware`).
- The build runs a Linux VM, so the builder needs **KVM** available.
- `version` picks the macOS recovery release: pre-Monterey has no Bluetooth
  firmware, and Sequoia drops firmware for the 2018/2019 MacBook Air, so
  `sonoma` is the default.
- `tahoe` (macOS 26, the last Intel release) has the **newest** Wi-Fi firmware
  a T2 Mac can get — `9.30.514.0.32.5.94` on a BCM4364B3, against Sonoma's
  `9.30.503.0.32.5.92` — but ships **no Wi-Fi firmware at all** for
  `brcmfmac4355c1` (MacBookPro15,x) or `brcmfmac4377b3` (MacBookPro16,2/16,3);
  of those two chips only the `brcmbt4377b3` Bluetooth pair survives, which is
  no use without Wi-Fi. It is an option, not the default; pick it only on a
  model Tahoe still supports.
- `tahoe` is pinned to Apple's *latest* offer for the board rather than to a
  fixed release, because no Intel Mac shipped with Tahoe and `osType =
  "default"` therefore cannot reach it. A macOS 26.x recovery refresh will
  break its fixed-output hash; re-pin it when that happens.
- A BaseSystem recovery image carries fewer regional NVRAM variants than an
  installed macOS, so the extracted set is a subset of what copying the blobs
  out of a running system would give. This affects only the per-region `.txt`
  files, not the firmware a given board loads.
