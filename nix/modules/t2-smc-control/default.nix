# NixOS module for t2-smc-control.
#
# Two pieces:
#   * the GTK GUI (temperatures, thermal pressure, battery state, SMC RTC). It
#     only *reads* the charge limit now; the limit itself is set through the
#     t2sbs Smart Battery driver's `charge_control_end_threshold` on BAT0 (the
#     desktop's battery settings / UPower), so the old applesmc chmod udev rule
#     is gone.
#   * the battery-gauging daemon. Mirrors upstream's
#     apps/t2-smc-control/systemd/t2-smc-gaugingd.service (which hardcodes
#     /usr/local/bin and so can't be consumed directly): a root
#     `t2-smc-control --daemon` that lifts the charge limit for a full
#     calibration charge like macOS powerd. Its state file
#     /var/lib/t2-smc-control/gauging is provided by StateDirectory.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-smc-control;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
in
{
  options.services.t2-smc-control = {
    # Retired by upstream's t2sbs move. Kept as hidden no-ops that warn (not
    # mkRemovedOptionModule errors) so existing configs keep evaluating.
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      visible = false;
      description = "Obsolete; has no effect.";
    };
    enableChargeLimitRule = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      visible = false;
      description = "Obsolete; has no effect.";
    };

    enable = lib.mkEnableOption "the T2 Mac SMC GUI and battery-gauging daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-smc-control/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-smc-control/package.nix { }";
      description = "The t2-smc-control package providing the GUI and the gauging daemon.";
    };

    gauging.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `t2-smc-gaugingd`, which temporarily lifts the SMC charge limit for
        a full charge when the battery gauge needs recalibration (DOD0 stale for
        3 days, Qmax for 14, or no full charge for 21), as macOS powerd does.
        Upstream's installer enables it unconditionally.
      '';
    };
  };

  config = lib.mkMerge [
    {
      warnings =
        lib.optional (cfg.users != [ ]) ''
          services.t2-smc-control.users has no effect and can be removed: the
          GUI only reads the charge limit, which is now set through the t2sbs
          `charge_control_end_threshold` on BAT0 (desktop battery settings).
        ''
        ++ lib.optional (cfg.enableChargeLimitRule != null) ''
          services.t2-smc-control.enableChargeLimitRule has no effect and can be
          removed: t2-smc-control no longer writes the charge limit; set it
          through the t2sbs `charge_control_end_threshold` on BAT0.
        '';
    }
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
      services.kait2en-app-folder.apps = [ "org.t2smccontrol.gtk.desktop" ];

      # Mirrors systemd/t2-smc-gaugingd.service.
      systemd.services.t2-smc-gaugingd = lib.mkIf cfg.gauging.enable {
        description = "T2 SMC battery gauging mitigation";
        after = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";
          ExecStart = "${lib.getExe cfg.package} --daemon";
          Restart = "on-failure";
          RestartSec = 10;
          StateDirectory = "t2-smc-control";
        };
      };
    })
  ];
}
