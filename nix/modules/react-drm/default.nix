# NixOS module for react-drm, the T2 Touch Bar runtime.
#
# Upstream's install.sh performs three pieces of system integration that this
# module reproduces declaratively:
#
#   1. udev rules (apps/react-drm/system/99-react-drm.rules): assign the Touch
#      Bar DRM card + touch input to their own logind seat, make the Touch Bar
#      USB config / backlight sysfs nodes group-writable (video), and let the
#      input group open /dev/uinput. The shipped rules call /bin/chown and
#      /bin/chmod, which do not exist on NixOS, so they are rewritten to
#      coreutils store paths here.
#   2. group memberships: the session user must be in `video` (config switching
#      + backlight) and `input` (uinput key injection).
#   3. a systemd *user* service (apps/react-drm/system/react-drm.service) that
#      starts the compiled app at login and runs the detach helper on stop.
#      Upstream points it at the user's home checkout; we point it at the Nix
#      store build instead.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.react-drm;

  # The shipped udev rules invoke /bin/chown and /bin/chmod, absent on NixOS.
  # Rewrite them to coreutils store paths so RUN+= works. Installed as a
  # rules.d tree (not read back as a string) so this stays a plain build-time
  # dependency: reading a derivation's contents at eval time (IFD) would force
  # `${cfg.package}` — the whole react-drm npm/tsc/node-gyp build — to run
  # during evaluation, e.g. inside a fleet cache-probe that only means to
  # evaluate toplevels.
  udevRules = pkgs.runCommand "react-drm-udev-rules" { } ''
    mkdir -p "$out/etc/udev/rules.d"
    substitute ${cfg.package}/share/react-drm/system/99-react-drm.rules \
      "$out/etc/udev/rules.d/99-react-drm.rules" \
      --replace-fail '/bin/chown' '${pkgs.coreutils}/bin/chown' \
      --replace-fail '/bin/chmod' '${pkgs.coreutils}/bin/chmod'
  '';

  appDir = "${cfg.package}/lib/react-drm";
  detachHelper = "${cfg.package}/share/react-drm/system/react-drm-tb-detach";
in
{
  options.services.react-drm = {
    enable = lib.mkEnableOption "the react-drm Touch Bar runtime (udev rules + user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/react-drm/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/react-drm/package.nix { }";
      description = "The react-drm package providing the compiled app and system/ assets.";
    };

    enableUserService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to define the `react-drm` systemd *user* service, started as part
        of the graphical session. Disable to manage the runtime yourself while
        still getting the udev rules and group memberships.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "alice" ]'';
      description = ''
        Users to add to the `video` and `input` groups, required for the Touch
        Bar config switching, backlight control and uinput key injection.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The udev rules reference the `video` and `input` groups; both exist by
    # default on NixOS. Drop the rules in as a package so udev collects them
    # from the store at system-build time — no IFD (see udevRules above).
    services.udev.packages = [ udevRules ];

    # Touch Bar key injection needs /dev/uinput present.
    boot.kernelModules = [ "uinput" ];

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [
        "video"
        "input"
      ];
    });

    systemd.user.services.react-drm = lib.mkIf cfg.enableUserService {
      description = "react-drm touch bar UI";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      environment.NODE_ENV = "production";

      serviceConfig = {
        WorkingDirectory = "${appDir}/linux-touchbar-control-center";
        ExecStart = "${lib.getExe pkgs.nodejs} ${appDir}/linux-touchbar-control-center/dist/index.js";
        # Prefixed with '-' so a failing detach does not fail the unit stop.
        ExecStopPost = "-${detachHelper}";
        # The app treats SIGINT as shutdown and ignores SIGTERM.
        KillSignal = "SIGINT";
        SuccessExitStatus = "130 137 SIGINT";
        TimeoutStartSec = 180;
        TimeoutStopSec = 150;
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
