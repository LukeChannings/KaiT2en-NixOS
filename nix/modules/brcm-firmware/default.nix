# NixOS module for declarative T2 Mac Wi-Fi and Bluetooth firmware.
#
# The Fedora path copies the Broadcom blobs out of an installed macOS by hand
# (see the firmware howto). This module is the automatic alternative ported from
# nixos-hardware's apple/t2: it builds ../../pkgs/brcm-firmware, which downloads
# a macOS recovery image for the chosen version and extracts the brcm firmware
# inside a throwaway VM, then drops the result into hardware.firmware so the
# kernel finds it under /run/current-system/firmware.
#
# Caveats inherited from the build:
#   * The recovery image is fetched from Apple, so the firmware derivation needs
#     network access and is marked unfree — set
#     nixpkgs.config.allowUnfree = true (or allowlist "brcm-firmware").
#   * vmTools.runInLinuxVM means the build runs a small Linux VM; this needs KVM
#     (or binfmt) available on the builder.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.kait2en.firmware;
in
{
  options.hardware.kait2en.firmware = {
    enable = lib.mkEnableOption "automatic, declarative T2 Mac Wi-Fi and Bluetooth firmware (extracted from a macOS recovery image)";

    version = lib.mkOption {
      type = lib.types.enum [
        "monterey"
        "ventura"
        "sonoma"
        "tahoe"
      ];
      default = "sonoma";
      example = "tahoe";
      description = ''
        The macOS recovery version to extract the Broadcom firmware from.
        Versions before Monterey have no Bluetooth firmware; Sequoia drops
        firmware for the 2018/2019 MacBook Air, so `sonoma` is the safe default.

        `tahoe` (macOS 26) carries the newest Wi-Fi firmware available to a T2
        Mac, but ships none at all for the MacBookPro15,x (BCM4355) or
        MacBookPro16,2/16,3 (BCM4377) — only a BCM4377 Bluetooth pair survives,
        which is no use without Wi-Fi. Choose it only on a model Tahoe still
        supports — a MacBookPro16,1 (BCM4364) gains 9.30.514.0.32.5.94 over
        Sonoma's 9.30.503.0.32.5.92.

        `tahoe` is also the one version pinned to Apple's *latest* offer rather
        than a fixed release, so a macOS 26.x recovery refresh will break its
        fixed-output hash until it is re-pinned.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/brcm-firmware { inherit (cfg) version; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/brcm-firmware { inherit version; }";
      description = "The brcm-firmware package added to {option}`hardware.firmware`.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.firmware = [ cfg.package ];
  };
}
