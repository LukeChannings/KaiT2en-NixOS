# NixOS module for running ZFS on a T2 Mac: boots the KaiT2en kernel on the
# newest series OpenZFS supports, and enables ZFS.
#
# OpenZFS 2.4.4 (nixpkgs' `zfs`) supports kernels up to 7.2, so its kernel
# module is marked broken on the 7.3 series the KaiT2en kernel follows, and
# nixpkgs dropped linux_7_2 (end of life) on 2026-11-06. The flake's
# `nixpkgs-zfs` input pins the last nixos-unstable that still carries it
# (7.2.13, the final 7.2 release). Only the *base kernel* comes from there: it
# gets the same KaiT2en patches (nix/pkgs/kernel), and the kernelPackages set,
# ZFS (kernel module and userspace) and every KaiT2en out-of-tree module are
# built by the system's own nixpkgs. Both nixpkgs carry the same gcc (16.2.0),
# so the kernel and the modules agree on the toolchain.
#
# Not part of the aggregate `nixosModules.default`: it needs the pinned input,
# so the flake exports it as `nixosModules.kait2en-zfs` (this file applied to
# `{ inherit (inputs) nixpkgs-zfs; }`). Hosts still set `networking.hostId`.
#
# The gpu-runtime-pm series cannot follow: upstream rebased it onto 7.3, and
# 0003, 0006, 0007 and 0014 do not apply to 7.2.13. Hybrid MacBook Pros lose
# GMUX runtime PM (the dGPU stays powered) with this module, which asserts
# that `hardware.kait2en.gpuRuntimePm` is off rather than failing the build.
#
# Drop this module, its input and its check system once nixpkgs' `zfs`
# supports the series nix/pkgs/kernel selects.
{ nixpkgs-zfs }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.kait2en.zfs;
  pkgsZfs = nixpkgs-zfs.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Applied directly, like the default kernel in nix/modules/kait2en-kernel, so
  # the kernel's own `.override` survives `linuxPackagesFor`.
  kernel = import ../../pkgs/kernel {
    inherit pkgs;
    baseKernel = pkgsZfs.linux_7_2;
  };
in
{
  options.hardware.kait2en.zfs = {
    enable = lib.mkEnableOption ''
      ZFS on the KaiT2en kernel: boot it on the 7.2 series (from the flake's
      nixpkgs-zfs input), which OpenZFS supports, instead of 7.3, and enable
      ZFS. The GPU runtime PM amdgpu does not build on 7.2'';

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackagesFor kernel;
      defaultText = lib.literalExpression "pkgs.linuxPackagesFor (the KaiT2en kernel on nixpkgs-zfs' linux_7_2)";
      description = ''
        The kernelPackages set ZFS and the KaiT2en modules build against. Set
        as {option}`hardware.kait2en.kernelPackages`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.hardware.kait2en.gpuRuntimePm.enable;
        message = ''
          hardware.kait2en.zfs boots a ${cfg.kernelPackages.kernel.version} kernel, and the
          gpu-runtime-pm series is rebased onto 7.3 (0003, 0006, 0007 and 0014
          do not apply). Set hardware.kait2en.gpuRuntimePm.enable = false; the
          dGPU then stays powered under t2-hybrid-gpu-control.
        '';
      }
    ];

    hardware.kait2en.kernelPackages = cfg.kernelPackages;
    boot.supportedFilesystems.zfs = lib.mkDefault true;
  };
}
