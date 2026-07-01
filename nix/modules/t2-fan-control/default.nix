# NixOS module for t2-fan-control.
#
# Upstream ships a system service (apps/t2-fan-control/systemd/t2-fancontrol.service)
# that runs the GTK binary in `--daemon` mode as root. The daemon owns the fan
# sysfs nodes and exposes a Unix socket under /run/t2-fancontrol (mode 0666) that
# the unprivileged GUI connects to. This module reproduces that unit natively and
# installs the GUI (with its .desktop entry + icon) into the system profile.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-fan-control;
in
{
  options.services.t2-fan-control = {
    enable = lib.mkEnableOption "the T2 Mac fan control daemon and GTK GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-fan-control/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-fan-control/package.nix { }";
      description = "The t2-fan-control package providing t2-fancontrol-gtk.";
    };

    installGui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to add the package to {option}`environment.systemPackages`, so the
        GTK GUI, its desktop entry and icon are available. The daemon runs
        regardless; this only controls the user-facing GUI.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mkIf cfg.installGui [ cfg.package ];

    systemd.services.t2-fancontrol = {
      description = "T2 Fan Control daemon";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} --daemon";
        # Backstop the daemon's in-process SIGTERM handler: release the fans
        # back to SMC auto control even if the daemon was SIGKILLed or crashed,
        # so they are never left latched in manual mode with the firmware's
        # protective max-on-hot curve disabled.
        ExecStopPost = "${lib.getExe cfg.package} --release";
        Restart = "always";
        RestartSec = 2;
        # The daemon creates /run/t2-fancontrol itself, but letting systemd own
        # the RuntimeDirectory means it is recreated on every start and cleaned
        # up on stop. 0755 matches the directory mode the daemon sets (the
        # socket itself is widened to 0666 by the daemon for GUI access).
        RuntimeDirectory = "t2-fancontrol";
        RuntimeDirectoryMode = "0755";
      };
    };
  };
}
