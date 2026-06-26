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
  version = "sonoma"; # or "ventura" / "monterey"
};
```

or use the package directly through the flake overlay
(`pkgs.kait2en.brcm-firmware`, or `pkgs.kait2en.brcm-firmwareFor "ventura"`).

## Constraints

- The firmware derivation is **unfree** — set
  `nixpkgs.config.allowUnfree = true` (or allowlist `brcm-firmware`).
- The build runs a Linux VM, so the builder needs **KVM** available.
- `version` picks the macOS recovery release: pre-Monterey has no Bluetooth
  firmware, and Sequoia drops firmware for the 2018/2019 MacBook Air, so
  `sonoma` is the default.
