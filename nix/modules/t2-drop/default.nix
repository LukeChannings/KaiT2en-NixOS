# NixOS module for t2-drop (AirDrop over AWDL).
#
# Mirrors apps/t2-drop (Makefile `install`):
#   * t2-drop.service (systemd/t2-drop.service, hardcodes /usr/local/bin):
#     Type=dbus, started by D-Bus activation when a program looks for AirDrop
#     receivers or registers to receive; it exits after a minute without
#     either. No [Install]. It runs `ip` to bring awdl0 up and `nmcli` to
#     unmanage it, so both are on the unit's PATH.
#   * the system-bus policy and activation file (dbus/org.t2drop.{conf,service})
#     via services.dbus.packages.
#   * networkmanager/90-t2-drop-awdl.conf: NetworkManager leaves awdl*
#     unmanaged (it appends with `+=`, so it composes with 10-t2-services.conf
#     and the NixOS-rendered main config).
#
# Needs the patched brcmfmac's AWDL interface (hardware.kait2en.wireless) and
# Bluetooth for the BLE sender scan. install-apps.sh installs it on every T2
# Mac; it is inert until something asks for it over D-Bus.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-drop;
  nm = config.networking.networkmanager;
in
{
  options.services.t2-drop = {
    enable = lib.mkEnableOption "T2 Drop, AirDrop to and from Apple devices over AWDL (`t2drop`)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-drop/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-drop/package.nix { }";
      description = "The t2-drop package.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!config.hardware.kait2en.wireless.enable) ''
      services.t2-drop needs the AWDL interface of the patched brcmfmac;
      enable hardware.kait2en.wireless.
    '';

    # The BLE sender scan; Fedora runs bluetoothd by default.
    hardware.bluetooth.enable = lib.mkDefault true;

    environment.systemPackages = [ cfg.package ];
    services.dbus.packages = [ cfg.package ];

    environment.etc."NetworkManager/conf.d/90-t2-drop-awdl.conf" = lib.mkIf nm.enable {
      source = "${cfg.package}/share/t2-drop/90-t2-drop-awdl.conf";
    };

    # Mirrors systemd/t2-drop.service.
    systemd.services.t2-drop = {
      description = "T2 Drop, AirDrop to Apple devices over AWDL";
      documentation = [ "https://github.com/kaiT2en/KaiT2en-Fedora" ];
      path = [ pkgs.iproute2 ] ++ lib.optional nm.enable nm.package;
      serviceConfig = {
        Type = "dbus";
        BusName = "org.t2drop";
        ExecStart = "${lib.getExe cfg.package} daemon";
      };
    };
  };
}
