# NixOS module for t2-autobrightness.
#
# Mirrors t2-services/t2-autobrightness (Makefile `install`) and
# scripts/fedora/install-autobrightness.sh:
#   * kait2en-t2-autobrightness.service, a *user* unit
#     (integration/systemd/kait2en-t2-autobrightness.service, @BINDIR@ resolved
#     to the store), enabled globally (`systemctl --global enable`) by wanting
#     it from graphical-session.target. On Macs without the sensor or without
#     a built-in panel the daemon exits right away.
#   * the GNOME Shell extension kait2en-autobrightness@kait2en, installed
#     through the package; the daemon enables it itself.
#
# Upstream asks before installing it (install.sh `ask_autobrightness`): while
# it runs, GNOME's own automatic brightness and idle dimming are switched off.
# So it is opt-in here too, and no profile enables it. GNOME-only.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-autobrightness;
in
{
  options.services.t2-autobrightness = {
    enable = lib.mkEnableOption ''
      macOS-like automatic display brightness from the ambient light sensor
      (GNOME only; switches GNOME's own automatic brightness and idle dimming
      off while it runs)'';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../t2-services/t2-autobrightness/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../t2-services/t2-autobrightness/package.nix { }";
      description = "The t2-autobrightness package.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!(config.services.desktopManager.gnome.enable or false)) ''
      services.t2-autobrightness drives the panel through GNOME Shell
      (org.gnome.Shell.Brightness) and does nothing on other desktops.
    '';

    environment.systemPackages = [ cfg.package ];

    # Mirrors integration/systemd/kait2en-t2-autobrightness.service.
    systemd.user.services.kait2en-t2-autobrightness = {
      description = "KaiT2en automatic display brightness";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
