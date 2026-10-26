# NixOS module for t2-zone-power, upstream's replacement for t2-cpu-control.
#
# Installs the GUI and runs `t2-zonepowerd`, mirroring
# apps/t2-zone-power/systemd/t2-zonepowerd.service (which hardcodes
# /usr/local/bin and so can't be consumed directly): a root
# `t2-zonepower-gtk --daemon` that applies the SMC power-limit steps and
# restores every limit on exit. It keeps no state on disk.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-zone-power;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
in
{
  options.services.t2-zone-power = {
    enable = lib.mkEnableOption "t2-zonepowerd, which applies the T2 SMC power-limit steps, and its monitor GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-zone-power/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-zone-power/package.nix { }";
      description = "The t2-zone-power package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.kait2en-utilities.apps = [ "org.t2zonepower.gtk.desktop" ];

    # Mirrors systemd/t2-zonepowerd.service.
    systemd.services.t2-zonepowerd = {
      description = "T2 Zone Power daemon";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = "${lib.getExe cfg.package} --daemon";
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
