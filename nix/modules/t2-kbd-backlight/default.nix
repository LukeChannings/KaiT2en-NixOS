# NixOS module for t2-kbd-backlight.
#
# Runs the keyboard backlight idle-timeout daemon, mirroring
# apps/t2-kbd-backlight/systemd/t2-kbd-backlight.service (hardcodes
# /usr/local/bin, so defined natively here, hardening included):
#   * config: /etc/kait2en/kbd-backlight.toml, rendered from `settings`
#     (upstream seeds it once from config/kbd-backlight.toml and never
#     overwrites it; here it is declarative). The unit restarts on change, as
#     upstream's comment asks of the user.
#   * the level is set through UPower's KbdBacklight, so UPower is enabled.
#
# Upstream moved the backlight timeout out of the Touch Bar daemon into this
# one (7f497a1): without it, no T2 MacBook dims its keyboard on idle any more.
# install-apps.sh installs it on every model with a keyboard backlight (all T2
# MacBooks).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-kbd-backlight;
  settingsFormat = pkgs.formats.toml { };
  configFile = settingsFormat.generate "kbd-backlight.toml" cfg.settings;
in
{
  options.services.t2-kbd-backlight = {
    enable = lib.mkEnableOption "the T2 keyboard backlight idle-timeout daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-kbd-backlight/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-kbd-backlight/package.nix { }";
      description = "The t2-kbd-backlight package.";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "With `false` the daemon exits at start and leaves the backlight alone.";
          };
          idle_timeout_ms = lib.mkOption {
            type = lib.types.ints.between 5000 3600000;
            default = 30000;
            description = ''
              Idle time without keyboard, trackpad or Touch Bar input before
              the backlight fades out.
            '';
          };
        };
      };
      default = { };
      description = "Contents of /etc/kait2en/kbd-backlight.toml (upstream's config/kbd-backlight.toml).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."kait2en/kbd-backlight.toml".source = configFile;

    services.upower.enable = true;

    # Mirrors systemd/t2-kbd-backlight.service.
    systemd.services.t2-kbd-backlight = {
      description = "T2 keyboard backlight idle timeout";
      after = [
        "upower.service"
        "systemd-udevd.service"
      ];
      wants = [ "upower.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ configFile ];
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 2;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
      };
    };
  };
}
