# NixOS module for the model-exclusive GPU control apps.
#
# From upstream's install-apps.sh, a T2 Mac gets exactly one of these (or
# neither):
#
#   MacBookPro15,1                 -> t2-hybrid-gpu-control
#   MacBookPro15,3 / 16,1 / 16,4   -> t2-dgpu-control
#   others                         -> neither
#
# `hardware.kait2en.gpuControl.mode` selects which package (and, for dgpu, which
# systemd units) is installed. Profiles set it per the table above.
#
# dgpu units: the app toggles four units via `systemctl enable/disable`. NixOS
# owns unit files declaratively, so we define them natively (exact names +
# semantics: ConditionPathExists, before/after, sleep.target ExecStop) pointing
# at the package's $out/libexec/t2-dgpu-control-helper, and enable the chosen
# subset. The shipped unit files (which hardcode /usr/local/libexec) are not
# used.
#
# hybrid keeps its state in /run and ships no units; selecting it defines none,
# so the legacy dgpu units are simply absent.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.kait2en.gpuControl;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
  dgpuHelper = "${cfg.dgpuPackage}/libexec/t2-dgpu-control-helper";
in
{
  options.hardware.kait2en.gpuControl = {
    mode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "dgpu"
          "hybrid"
        ]
      );
      default = null;
      description = ''
        Which GPU control app to install, matching this Mac's model:
        `"dgpu"` (MacBookPro15,3 / 16,1 / 16,4), `"hybrid"` (MacBookPro15,1),
        or `null` for models with neither.
      '';
    };

    powerOffDgpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        (dgpu mode) Power off the discrete GPU at boot and keep it suspendable
        across sleep — the battery-saving default. Enables the
        `kait2en-dgpu-off` and `kait2en-dgpu-suspend` services.
      '';
    };

    amdgpuPowerSaving = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        (dgpu mode) Apply the AMDGPU power-saving profile at boot and restore it
        after resume (for when the dGPU is kept on rather than powered off).
        Enables the `kait2en-amdgpu-profile` and `-resume` services.
      '';
    };

    dgpuPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-dgpu-control/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-dgpu-control/package.nix { }";
      description = "The t2-dgpu-control package.";
    };

    hybridPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-hybrid-gpu-control/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-hybrid-gpu-control/package.nix { }";
      description = "The t2-hybrid-gpu-control package.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "hybrid") {
      environment.systemPackages = [ cfg.hybridPackage ];
    })

    (lib.mkIf (cfg.mode == "dgpu") {
      environment.systemPackages = [ cfg.dgpuPackage ];

      systemd.services = {
        kait2en-dgpu-off = lib.mkIf cfg.powerOffDgpu {
          description = "Power off the discrete GPU after boot";
          unitConfig.ConditionPathExists = "/sys/kernel/debug/vgaswitcheroo/switch";
          after = [ "systemd-modules-load.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${dgpuHelper} power-off";
          };
        };

        kait2en-dgpu-suspend = lib.mkIf cfg.powerOffDgpu {
          description = "Keep an intentionally powered-off dGPU suspendable";
          before = [ "sleep.target" ];
          unitConfig.StopWhenUnneeded = true;
          wantedBy = [ "sleep.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "-${dgpuHelper} prepare-suspend";
            ExecStop = "-${dgpuHelper} restore-after-resume";
          };
        };

        kait2en-amdgpu-profile = lib.mkIf cfg.amdgpuPowerSaving {
          description = "Apply the AMDGPU power-saving profile";
          after = [ "systemd-modules-load.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${dgpuHelper} apply-power-saving";
          };
        };

        kait2en-amdgpu-profile-resume = lib.mkIf cfg.amdgpuPowerSaving {
          description = "Restore the AMDGPU power-saving profile after resume";
          before = [ "sleep.target" ];
          unitConfig.StopWhenUnneeded = true;
          wantedBy = [ "sleep.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
            ExecStop = "${dgpuHelper} apply-power-saving";
          };
        };
      };
    })
  ];
}
