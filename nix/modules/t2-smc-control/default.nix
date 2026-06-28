# NixOS module for t2-smc-control.
#
# Unlike the other apps, t2-smc-control ships no systemd unit or udev rule: it
# is a plain GTK GUI. Its one piece of system integration is write access to the
# applesmc `battery_charge_limit` sysfs node — upstream gets this at runtime by
# shelling out to `pkexec chmod a+w` (see src/main.rs). This module installs the
# GUI and, optionally, a udev rule that makes that node group-writable (video)
# up front, so the charge-limit slider works without a per-session pkexec prompt.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-smc-control;
in
{
  options.services.t2-smc-control = {
    enable = lib.mkEnableOption "the T2 Mac SMC temperatures and battery charge-limit GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-smc-control/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-smc-control/package.nix { }";
      description = "The t2-smc-control package providing the GTK GUI.";
    };

    enableChargeLimitRule = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install a udev rule making the applesmc
        `battery_charge_limit` sysfs node writable by the `video` group, so the
        GUI can change the charge limit without a `pkexec` prompt. Users wanting
        to set the limit must be in the `video` group (see {option}`users`).
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "alice" ]'';
      description = ''
        Users to add to the `video` group, granting write access to
        `battery_charge_limit` when {option}`enableChargeLimitRule` is set.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # applesmc exposes battery_charge_limit under its hwmon device. Make it
    # group-writable (video) so the GUI's prepare_charge_limit_access() finds it
    # already writable and skips the pkexec path entirely.
    services.udev.extraRules = lib.mkIf cfg.enableChargeLimitRule ''
      ACTION=="add|change", SUBSYSTEM=="hwmon", DRIVERS=="applesmc", RUN+="${pkgs.bash}/bin/sh -c 'p=/sys%p/battery_charge_limit; [ -e \"$$p\" ] && ${pkgs.coreutils}/bin/chgrp video \"$$p\" && ${pkgs.coreutils}/bin/chmod g+w \"$$p\"'"
    '';

    users.users = lib.mkIf cfg.enableChargeLimitRule (
      lib.genAttrs cfg.users (_: {
        extraGroups = [ "video" ];
      })
    );
  };
}
