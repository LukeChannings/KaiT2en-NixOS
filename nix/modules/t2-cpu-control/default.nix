# NixOS module for t2-cpu-control.
#
# The GUI + polkit policy come from the package (in environment.systemPackages).
# On top of that the app persists CPU power limits and re-applies them at boot
# and after resume. Upstream ships a t2-cpu-control.service (ExecStart=
# t2-cpu-control-helper apply-saved, RemainAfterExit) and a system-sleep resume
# hook; both hardcode /usr/local/libexec, so we define them natively here,
# pointing at the package's $out/libexec/t2-cpu-control-helper.
#
# State path: the packaged helper is patched to write its saved config to
# /var/lib/t2-cpu-control/config (read-only /etc is unusable on NixOS); it also
# keeps thermald state under /var/lib/t2-cpu-control. We provision that dir with
# tmpfiles. /run/t2-cpu-control is a tmpfs RuntimeDirectory the helper creates.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-cpu-control;
  helper = "${cfg.package}/libexec/t2-cpu-control-helper";
in
{
  options.services.t2-cpu-control = {
    enable = lib.mkEnableOption "the T2 CPU power-limit control GUI + persistence";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-cpu-control/package.nix {
        branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
      };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-cpu-control/package.nix { }";
      description = "The t2-cpu-control package (GUI, helpers and polkit policy).";
    };

    persist = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to re-apply the saved CPU power limits at boot and after resume
        (the `apply-saved` helper verb). Disable to run the GUI without the
        persistence service.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # rdmsr/wrmsr need /dev/cpu/*/msr; the helper modprobes `msr` itself, but
    # make sure the device nodes exist.
    boot.kernelModules = [ "msr" ];

    # Writable state dir the helper saves its config + thermald state into
    # (see the package's --replace of /etc/t2-cpu-control.conf).
    systemd.tmpfiles.rules = lib.mkIf cfg.persist [
      "d /var/lib/t2-cpu-control 0755 root root -"
    ];

    # Re-apply saved limits at boot.
    systemd.services.t2-cpu-control = lib.mkIf cfg.persist {
      description = "Apply persistent T2 CPU power limits";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${helper} apply-saved";
        RemainAfterExit = true;
      };
    };

    # Re-apply saved limits after resume (mirrors the shipped system-sleep hook).
    systemd.services.t2-cpu-control-resume = lib.mkIf cfg.persist {
      description = "Re-apply T2 CPU power limits after resume";
      after = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      wantedBy = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${helper} apply-saved";
      };
    };
  };
}
