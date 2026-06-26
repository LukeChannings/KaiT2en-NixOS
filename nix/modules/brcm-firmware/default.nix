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
      ];
      default = "sonoma";
      example = "ventura";
      description = ''
        The macOS recovery version to extract the Broadcom firmware from.
        Versions before Monterey have no Bluetooth firmware; Sequoia drops
        firmware for the 2018/2019 MacBook Air, so `sonoma` is the safe default.
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
