# NixOS module for t2-airshare (Quick Share + AirDrop).
#
# Mirrors apps/t2-airshare (Makefile `install`):
#   * the app, CLI and file-manager "Send with T2 AirShare" integrations, via
#     the package; the app joins the KaiT2en app folder.
#   * t2-airshare.service, the per-user receiver (systemd/t2-airshare.service,
#     WantedBy=graphical-session.target). Upstream installs it but does not
#     enable it: the app's receive toggle runs `systemctl --user
#     enable|disable` on it. So it is the one unit shipped as a *file*
#     (systemd.packages, ExecStart rewritten by the package) rather than
#     re-declared natively: a native unit has no [Install] section, and the
#     toggle would fail.
#   * t2-quickshare-hotspot.service (systemd/t2-quickshare-hotspot.service,
#     hardcodes /usr/local/libexec): the root helper, D-Bus activated
#     (org.t2airshare.QuickShareHotspot) when a Bluetooth transfer moves to
#     Wi-Fi, exits after a minute idle. Defined natively; it runs iw, ip and
#     nmcli, so those are on its PATH. Bus policy + activation file via
#     services.dbus.packages.
#
# AirDrop goes through t2-drop (org.t2drop), so services.t2-drop comes with
# it. install-apps.sh installs it on every T2 Mac.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-airshare;
  nm = config.networking.networkmanager;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
in
{
  options.services.t2-airshare = {
    enable = lib.mkEnableOption "T2 AirShare, Quick Share and AirDrop file sharing";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-airshare/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-airshare/package.nix { }";
      description = "The t2-airshare package.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!nm.enable) ''
      services.t2-airshare moves Bluetooth Quick Share transfers onto a Wi-Fi
      hotspot through NetworkManager; without it only transfers over a
      shared Wi-Fi work.
    '';

    environment.systemPackages = [ cfg.package ];
    services.kait2en-utilities.apps = [ "org.t2airshare.gtk.desktop" ];
    services.dbus.packages = [ cfg.package ];
    # NixOS takes user units from systemd.packages too (lib/systemd/user).
    systemd.packages = [ cfg.package ];

    services.t2-drop.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;

    # Mirrors systemd/t2-quickshare-hotspot.service.
    systemd.services.t2-quickshare-hotspot = {
      description = "T2 AirShare hotspot for Quick Share transfers over Bluetooth";
      documentation = [ "https://github.com/kaiT2en/KaiT2en-Fedora" ];
      after = [ "NetworkManager.service" ];
      path = [
        pkgs.iw
        pkgs.iproute2
      ]
      ++ lib.optional nm.enable nm.package;
      serviceConfig = {
        Type = "dbus";
        BusName = "org.t2airshare.QuickShareHotspot";
        ExecStart = "${cfg.package}/libexec/t2-quickshare-hotspot";
      };
    };
  };
}
