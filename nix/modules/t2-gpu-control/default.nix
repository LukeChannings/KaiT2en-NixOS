# NixOS module for the model-exclusive GPU control apps.
#
# From upstream's install-apps.sh, a T2 Mac gets exactly one of these (or
# neither):
#
#   MacBookPro15,1 / 16,1 / 16,4   -> t2-hybrid-gpu-control
#   MacBookPro15,3                 -> t2-dgpu-control
#   others                         -> neither
#
# `hardware.kait2en.gpuControl.mode` selects which package (and, for dgpu, which
# systemd units) is installed. Profiles set it per model.
#
# hybrid needs upstream's gpu-runtime-pm amdgpu (GMUX runtime PM): without it
# vga_switcheroo never reports DynPwr/DynOff and the hybrid helper refuses to
# enable. Enable `hardware.kait2en.gpuRuntimePm` alongside it (the profiles
# do; a warning fires otherwise).
#
# hybrid also installs upstream's contrib/90-kait2en-gsk-renderer.conf into
# /etc/environment.d (GSK_RENDERER=ngl: GTK's Vulkan renderer would open the
# AMD render node and wake the dGPU on every GTK app start). Upstream's
# `flatpak override --system --env=GSK_RENDERER=ngl` is not mirrored.
#
# hybrid's runtime-PM enablement is a one-shot runtime action in the app's
# helper (`enable-hybrid` writes power/control=auto, state in /run) and does
# not survive a reboot, so `hybridAtBoot` (default on) applies that half
# declaratively: a udev rule sets the AMD dGPU's power/control to `auto` on
# add, and the iGPU (always pci-0000:00:02.0 on these Intel Macs) is tagged as
# mutter's preferred primary render GPU so the desktop renders on the GPU that
# scans out instead of reverse-PRIMEing every frame off the dGPU (~16 W at
# idle for nothing). switcherooControl adds per-app PRIME offload on top
# (GNOME's "Launch using Discrete Graphics Card" / `switcherooctl launch`).
# The EFI gpu-power-prefs boot-GPU choice stays with the app's
# enable-hybrid/use-discrete; turn hybridAtBoot off if you boot on the
# discrete GPU.
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
  hybridHelper = "${cfg.hybridPackage}/libexec/t2-hybrid-gpu-control-helper";
  esp = config.boot.loader.efi.efiSysMountPoint;
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
        `"hybrid"` (MacBookPro15,1 / 16,1 / 16,4; needs
        {option}`hardware.kait2en.gpuRuntimePm.enable`), `"dgpu"`
        (MacBookPro15,3), or `null` for models with neither.
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

    hybridAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        (hybrid mode) Declaratively apply at boot what the app's "Enable hybrid
        graphics" applies at runtime: allow the dGPU to autosuspend
        (`power/control=auto`, reaching D3cold via the gpu-runtime-pm amdgpu's
        GMUX callbacks) and tag the iGPU as mutter's preferred primary render
        GPU, plus switcherooControl for per-app PRIME offload. Disable if you
        boot on the discrete GPU (gpu-power-prefs set to discrete).
      '';
    };

    hybridPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-hybrid-gpu-control/package.nix {
        inherit branding;
        espMountPoint = esp;
      };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-hybrid-gpu-control/package.nix { }";
      description = "The t2-hybrid-gpu-control package.";
    };

    hybridPreboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        (hybrid mode) Install upstream's `t2-gpu-preboot` UEFI image on the ESP
        and boot it before the loader, so a Linux boot that follows macOS comes
        back up on the integrated GPU instead of the discrete one. Only useful
        if you actually boot macOS: macOS rewrites the `gpu-power-prefs` EFI
        variable every time, and the firmware reads it during POST, which is
        too early for anything running under Linux to correct. The image puts
        the variable back and warm resets.

        Off by default, unlike upstream's installer, because switching it on
        writes to the machine's NVRAM: it adds a "KaiT2en GPU" boot entry and
        moves it to the front of BootOrder, which is not something a
        `nixos-rebuild` would otherwise do.

        Setting it back to `false` stops the image being installed, but the
        NVRAM entry is not NixOS' to garbage-collect -- clear it by hand
        before you switch, with
        `t2-hybrid-gpu-control-helper remove-preboot`.

        Needs {option}`boot.loader.systemd-boot.enable`.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.mode == "hybrid") {
      warnings = lib.optional (!config.hardware.kait2en.gpuRuntimePm.enable) ''
        hardware.kait2en.gpuControl.mode = "hybrid" without
        hardware.kait2en.gpuRuntimePm.enable: the stock amdgpu has no GMUX
        runtime PM, so t2-hybrid-gpu-control cannot power the dGPU down.
      '';
      environment.systemPackages = [ cfg.hybridPackage ];
      services.kait2en-utilities.apps = [ "org.t2hybridgpucontrol.gtk.desktop" ];
      environment.etc."environment.d/90-kait2en-gsk-renderer.conf".source =
        ../../../apps/t2-hybrid-gpu-control/contrib/90-kait2en-gsk-renderer.conf;
    })

    (lib.mkIf (cfg.mode == "hybrid" && cfg.hybridPreboot) {
      assertions = [
        {
          assertion = config.boot.loader.systemd-boot.enable;
          message = ''
            hardware.kait2en.gpuControl.hybridPreboot needs
            boot.loader.systemd-boot: the UEFI image is placed on the ESP with
            boot.loader.systemd-boot.extraFiles, and the image chainloads
            systemd-boot by path. With GRUB, build the package with
            `chainload` pointing at grubx64.efi and copy the image onto the
            ESP yourself.
          '';
        }
      ];

      # The bootloader owns the ESP, so the image goes through it rather than
      # being copied in by an activation script.
      boot.loader.systemd-boot.extraFiles."EFI/kait2en/t2-gpu-preboot.efi" =
        "${cfg.hybridPackage}/share/t2-hybrid-gpu-control/t2-gpu-preboot.efi";

      # upstream Makefile `install`: `helper sync-preboot`. It is idempotent --
      # it creates the "KaiT2en GPU" entry only when absent, deletes duplicates
      # from older runs and moves the entry first in BootOrder only when it is
      # not already there -- so running it every boot is a no-op once settled.
      # Every boot is deliberate: `bootctl install` puts systemd-boot back at
      # the front of BootOrder whenever it runs, and this has to win.
      systemd.services.kait2en-gpu-preboot-sync = {
        description = "Keep the t2-gpu-preboot UEFI boot entry first in BootOrder";
        unitConfig.ConditionPathIsDirectory = "/sys/firmware/efi/efivars";
        after = [ "local-fs.target" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ cfg.hybridPackage ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${hybridHelper} sync-preboot";
        };
      };
    })

    (lib.mkIf (cfg.mode == "hybrid" && cfg.hybridAtBoot) {
      # The iGPU is matched by stable PCI path, not card index (which races);
      # the mutter tag name is read by libmutter
      # (udev_device_get_property "mutter-device-preferred-primary").
      services.udev.extraRules = ''
        SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="pci-0000:00:02.0", TAG+="mutter-device-preferred-primary"
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{class}=="0x030000", ATTR{power/control}="auto"
      '';

      services.switcherooControl.enable = lib.mkDefault true;
    })

    (lib.mkIf (cfg.mode == "dgpu") {
      environment.systemPackages = [ cfg.dgpuPackage ];
      services.kait2en-utilities.apps = [ "org.t2dgpucontrol.gtk.desktop" ];

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
