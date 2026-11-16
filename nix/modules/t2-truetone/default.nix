# NixOS module for t2-truetone.
#
# Mirrors apps/t2-truetone (Makefile `install`) and install.sh:
#   * the app and the `t2truetone` daemon/CLI, via the package; the app joins
#     the KaiT2en app folder. The GNOME Shell extension
#     kait2en-autobrightness@kait2en ships with it (share/gnome-shell/
#     extensions, found through the system profile); the daemon enables it.
#   * t2-truetone.service, the per-user session daemon (WantedBy=
#     graphical-session.target). A first install leaves it off and the user
#     turns it on in the app, whose Start/Stop runs `systemctl --user
#     enable|disable --now` on it. So it ships as a *file* (systemd.packages,
#     ExecStart rewritten by the package) rather than natively: a native unit
#     has no [Install] section, and the toggle would fail. Same exception as
#     t2-airshare.
#   * udev/70-t2-truetone.rules: uaccess on the ambient light sensor's hidraw
#     node (05ac:8262), via services.udev.packages.
#
# install-apps.sh installs it when the Mac has the ambient light sensor
# (`has_ambient_light_sensor`: every T2 MacBook, the iMac20,1 and the iMac
# Pro) and GNOME Shell is present, which is what the profiles do. Installing
# it changes nothing until a user starts it: while it runs, GNOME's own
# automatic brightness and idle dimming are off, and stopping it gives them
# back.
#
# It replaced t2-autobrightness (t2-services/t2-autobrightness). Upstream's
# install.sh migrates an enabled autobrightness user by enabling t2-truetone
# for them; a NixOS module cannot enable a unit per user, so the removed
# option says to turn it on in the app instead.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-truetone;
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "services" "t2-autobrightness" "enable" ] ''
      t2-autobrightness was replaced upstream by t2-truetone, which carries the
      automatic brightness. Enable services.t2-truetone and start it in the
      T2 TrueTone app (automatic brightness is on by default there).
    '')
    (lib.mkRemovedOptionModule [ "services" "t2-autobrightness" "package" ] ''
      t2-autobrightness was replaced upstream by t2-truetone; see
      services.t2-truetone.package.
    '')
  ];

  options.services.t2-truetone = {
    enable = lib.mkEnableOption ''
      T2 TrueTone: ambient white point adaptation, evening mode and automatic
      brightness from the ambient light sensor (GNOME only; started per user
      from its app)'';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-truetone/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-truetone/package.nix { }";
      description = "The t2-truetone package.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!(config.services.desktopManager.gnome.enable or false)) ''
      services.t2-truetone drives the panel through Mutter and GNOME Shell and
      does nothing on other desktops.
    '';

    environment.systemPackages = [ cfg.package ];
    services.kait2en-utilities.apps = [ "org.t2truetone.gtk.desktop" ];
    services.udev.packages = [ cfg.package ];
    # NixOS takes user units from systemd.packages too (lib/systemd/user).
    systemd.packages = [ cfg.package ];
  };
}
