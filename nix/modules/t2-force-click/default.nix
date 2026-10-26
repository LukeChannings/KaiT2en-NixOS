# NixOS module for t2-force-click.
#
# Installs the GUI and runs the root daemon, mirroring
# apps/t2-force-click/systemd/t2-force-click.service (hardcodes /usr/local/bin,
# so defined natively here):
#   * config: patched from /etc/t2-force-click/config.txt to
#     /var/lib/t2-force-click/config.txt → StateDirectory.
#   * socket dir /run/t2-force-click: the daemon creates it itself (0755) and
#     chmods the socket 0666; authorisation is by peer credentials, so it is
#     declared as a preserved RuntimeDirectory with the same mode.
#   * the deep-press action runs `runuser … sh -c <command>` and queries
#     `loginctl`, so bash/util-linux/systemd plus the system profile are on the
#     unit's PATH (the command inherits it via --preserve-environment).
# Requires the t2_precision_trackpad + t2_trackpad_actuator modules
# (hardware.kait2en loads both).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-force-click;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
in
{
  options.services.t2-force-click = {
    enable = lib.mkEnableOption "the T2 trackpad Force Click daemon and settings GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-force-click/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-force-click/package.nix { }";
      description = "The t2-force-click package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.kait2en-app-folder.apps = [ "org.t2forceclick.gtk.desktop" ];

    # Mirrors systemd/t2-force-click.service.
    systemd.services.t2-force-click = {
      description = "T2 Force Click daemon";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.bash
        pkgs.util-linux
        config.systemd.package
        "/run/wrappers"
        "/run/current-system/sw"
      ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = "${lib.getExe cfg.package} --daemon";
        Restart = "always";
        RestartSec = 2;
        StateDirectory = "t2-force-click";
        RuntimeDirectory = "t2-force-click";
        RuntimeDirectoryMode = "0755";
      };
    };
  };
}
