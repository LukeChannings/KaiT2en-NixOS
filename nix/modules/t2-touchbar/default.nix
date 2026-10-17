# NixOS module for kait2en-touchbar (apps/t2-touchbar), the T2 Touch Bar
# daemon that replaced react-drm upstream.
#
# Reproduces apps/t2-touchbar/install.sh + Makefile declaratively:
#
#   1. udev rules (integration/udev/99-zz-kait2en-touchbar.rules): put the
#      Touch Bar DRM card + digitizer on their own `seat-touchbar` seat, grant
#      the `kait2en-touchbar` group the panel, backlight, uinput, the internal
#      keyboard's Fn event node and the haptic actuator's `play` parameter, and
#      pull in the attach service when 05ac:8302 appears in configuration 1.
#      Shipped by the package with /bin/chgrp|chmod rewritten to coreutils.
#   2. the `kait2en-touchbar` system group + membership for {option}`users`
#      (install.sh `prepare_device_access`).
#   3. kait2en-touchbar-attach.service (system, mirrors
#      integration/systemd/system/kait2en-touchbar-attach.service): a root
#      oneshot running `kait2en-touchbar --attach` to switch the panel to its
#      display configuration. Upstream's
#      `ExecCondition=systemctl --global is-enabled kait2en-touchbar.service`
#      is dropped: here the attach unit only exists when the daemon is enabled.
#   4. kait2en-touchbar.service (user, mirrors
#      integration/systemd/user/kait2en-touchbar.service), the daemon itself,
#      with upstream's sandboxing kept verbatim.
#   5. /etc/kait2en/touchbar.toml, the system default config (users override it
#      with $XDG_CONFIG_HOME/kait2en-touchbar/config.toml).
#
# install.sh also disables tiny-dfr / react-drm; on NixOS the equivalent is an
# assertion against nixpkgs' tiny-dfr module.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-touchbar;
in
{
  options.services.t2-touchbar = {
    enable = lib.mkEnableOption "the kait2en-touchbar T2 Touch Bar daemon (udev rules, attach service, user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-touchbar/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-touchbar/package.nix { }";
      description = "The kait2en-touchbar package.";
    };

    enableUserService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to define the `kait2en-touchbar` systemd *user* service, started
        with the graphical session. Disable to run the daemon yourself while
        keeping the udev rules, group and attach service.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "alice" ]'';
      description = ''
        Users to add to the `kait2en-touchbar` group, which the udev rules grant
        the Touch Bar panel, backlight, uinput and Fn key access. The desktop
        user must be in it (log out/in or reboot after the first switch).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.hardware.apple.touchBar.enable or false);
        message = ''
          services.t2-touchbar and hardware.apple.touchBar (tiny-dfr) both drive
          the Touch Bar; enable only one (upstream's installer disables tiny-dfr).
        '';
      }
    ];

    services.udev.packages = [ cfg.package ];

    # Touch Bar key injection needs /dev/uinput.
    boot.kernelModules = [ "uinput" ];

    users.groups.kait2en-touchbar = { };
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "kait2en-touchbar" ];
    });

    environment.etc."kait2en/touchbar.toml".source =
      "${cfg.package}/share/kait2en-touchbar/touchbar.toml";

    # Pulled in by the udev rule (SYSTEMD_WANTS) and enabled for boot.
    systemd.services.kait2en-touchbar-attach = {
      description = "Attach the Apple T2 Touch Bar display interface";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cfg.package} --attach";
        TimeoutStartSec = 60;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    systemd.user.services.kait2en-touchbar = lib.mkIf cfg.enableUserService {
      description = "T2 Touch Bar";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # `wpctl` for the volume level (systemd-run, for custom keys, is on the
      # default unit PATH).
      path = [ config.services.pipewire.wireplumber.package ];
      unitConfig = {
        StartLimitIntervalSec = 30;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 2;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        PrivateTmp = true;
        PrivateIPC = true;
        ProtectKernelTunables = true;
        ReadWritePaths = [
          "-/sys/class/backlight/t2tb_backlight/brightness"
          "-/sys/class/backlight/appletb_backlight/brightness"
          "-/sys/module/t2_trackpad_actuator/parameters/play"
        ];
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
      };
    };
  };
}
