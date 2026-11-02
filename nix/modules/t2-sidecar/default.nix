# NixOS module for t2-sidecar.
#
# Mirrors apps/t2-sidecar/install.sh: installs `t2-sidecar` and defines its two
# *user* units natively (upstream's hardcode /usr/local):
#   * t2-sidecar.service — runs `t2-sidecar-display $T2_SIDECAR_MODE`, with the
#     mode from ~/.config/t2-sidecar/env (written by `t2-sidecar on MODE`). No
#     [Install]: `t2-sidecar on` starts it, `off` or logout stops it.
#   * t2-sidecar-sunshine.service — Sunshine bound to the virtual monitor.
#     Upstream gates it on `ConditionFileIsExecutable=/usr/local/bin/sunshine`,
#     i.e. their Sunshine fork with the V4L2 encoder (LizardByte/Sunshine#5717,
#     see website/docs/post-install/sidecar.md); stock Sunshine cannot encode
#     with the T2 yet. Here it is defined only when `sunshine.package` is set.
#     Without it `t2-sidecar on` just reports that Sunshine did not start.
#
# The T2 side is t2bce_sidecar (built with the t2bce stack, autoloaded) and the
# T2 link. GNOME-only (Mutter's virtual monitors). Upstream installs it on
# every T2 Mac; it does nothing without a Sunshine set up by hand, so it is
# opt-in here and no profile enables it.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-sidecar;
in
{
  options.services.t2-sidecar = {
    enable = lib.mkEnableOption "the Sidecar virtual display (`t2-sidecar on|off|status`; GNOME only)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-sidecar/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-sidecar/package.nix { }";
      description = "The t2-sidecar package.";
    };

    sunshine.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.sunshine.overrideAttrs { src = <the t2-sidecar branch of deqrocks/Sunshine>; }";
      description = ''
        A Sunshine able to encode with the T2 (V4L2 m2m), started and stopped
        together with the virtual monitor. Stock Sunshine lacks the V4L2
        encoder until LizardByte/Sunshine#5717 lands; upstream builds the
        `t2-sidecar` branch of deqrocks/Sunshine. `null` leaves Sunshine out.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Mirrors apps/t2-sidecar/t2-sidecar.service.
    systemd.user.services.t2-sidecar = {
      description = "KaiT2en Sidecar virtual display";
      documentation = [ "https://kait2en.org/documentation.html#streaming-using-sidecar" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "exec";
        EnvironmentFile = "-%h/.config/t2-sidecar/env";
        ExecStart = "${cfg.package}/libexec/t2-sidecar-display $T2_SIDECAR_MODE";
        Restart = "no";
      };
    };

    # Mirrors apps/t2-sidecar/t2-sidecar-sunshine.service.
    systemd.user.services.t2-sidecar-sunshine = lib.mkIf (cfg.sunshine.package != null) {
      description = "Sunshine for the KaiT2en Sidecar display";
      documentation = [ "https://kait2en.org/documentation.html#streaming-using-sidecar" ];
      bindsTo = [ "t2-sidecar.service" ];
      after = [ "t2-sidecar.service" ];
      serviceConfig = {
        Type = "exec";
        # Every virtual monitor is new to GNOME, so the saved screen choice is
        # void and Sunshine has to ask again.
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %h/.config/sunshine/portal_token.gnome";
        ExecStart = lib.getExe cfg.sunshine.package;
        Restart = "on-failure";
      };
    };
  };
}
