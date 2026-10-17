{
  description = "KaiT2en — Apple T2 Mac kernel modules and userspace apps, packaged for Nix";

  # CI (.github/workflows/nix.yml) pushes everything `nix flake check` builds
  # to this cache, so consumers and hardware smoke tests substitute the kernel
  # and modules instead of rebuilding them.
  nixConfig = {
    extra-substituters = [ "https://nix.channings.me" ];
    extra-trusted-public-keys = [ "garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    flake-compat.url = "https://git.lix.systems/lix-project/flake-compat/archive/main.tar.gz";
    flake-compat.flake = false;
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      let
        # Minimal per-profile NixOS systems used purely as build gates: does
        # the whole stack — patched kernel, every out-of-tree module, the app
        # packages, and the NixOS module wiring — still evaluate *and build*?
        # They are not installable systems (dummy root fs, no bootloader).
        # Wi-Fi/Bluetooth firmware is forced off: it is unfree and builds
        # inside a KVM VM, neither of which belongs in a CI gate.
        # `nix flake check` builds each toplevel via perSystem `checks` below.
        checkConfigurations =
          let
            mkCheckSystem =
              profile:
              nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                modules = [
                  profile
                  (
                    { lib, ... }:
                    {
                      fileSystems."/" = {
                        device = "/dev/disk/by-label/nixos";
                        fsType = "ext4";
                      };
                      boot.loader.grub.enable = false;
                      hardware.kait2en.firmware.enable = lib.mkForce false;
                      # A real install runs PipeWire; without it the t2bce-audio-dsp
                      # payload (patched PipeWire + WirePlumber + per-model DSP graphs)
                      # is inert and the gate would not build or cache it — the
                      # per-profile toplevels would even collapse to identical drvs.
                      services.pipewire.enable = true;
                      # Likewise NetworkManager: t2-services provisions the
                      # "Apple T2 Bridge" link-local profile through it.
                      networking.networkmanager.enable = true;
                      system.stateVersion = lib.versions.majorMinor lib.version;
                    }
                  )
                ];
              };
          in
          {
            check-macbookpro16-1 = mkCheckSystem ./nix/profiles/macbookpro16-1.nix;
            check-macbookpro16-4 = mkCheckSystem ./nix/profiles/macbookpro16-4.nix;
            check-macbookair9-1 = mkCheckSystem ./nix/profiles/macbookair9-1.nix;
          };
      in
      {
        # T2 Macs are Intel x86_64 hardware; nothing here targets other systems.
        systems = [ "x86_64-linux" ];

        # System-independent outputs.
        flake = {
          # `kernelModulesFor kernel` builds every KaiT2en module against an
          # arbitrary kernel — this is what NixOS' boot.extraModulePackages wants,
          # e.g. `config.boot.kernelPackages.kernel`. Exposed per-system as
          # `lib.<system>.kernelModulesFor`.
          lib = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (
            system:
            let
              pkgs = import nixpkgs { inherit system; };
            in
            {
              kernelModulesFor = kernel: pkgs.callPackage ./modules { inherit kernel; };

              # The KaiT2en kernel: the Fedora-matched base kernel (selected in
              # nix/pkgs/kernel — the single bump site) + the SPI-HID ABI patch
              # the out-of-tree T2 HID drivers compile against. Build the modules
              # against *this* (e.g. `kernelModulesFor kait2enKernel`).
              #
              # Applied directly (not via callPackage) so the result keeps the
              # *kernel's* own chainable `.override` — callPackage would wrap it
              # in makeOverridable, shadowing that with an override that only
              # takes `pkgs`, which breaks `pkgs.linuxPackagesFor` /
              # `boot.kernelPackages` (they call `kernel.override { features,
              # kernelPatches, randstructSeed }`).
              kait2enKernel = import ./nix/pkgs/kernel { inherit pkgs; };
            }
          );

          # NixOS modules for the userspace apps' system integration (systemd
          # units, udev rules, group memberships). Each module defaults its
          # package to `pkgs.callPackage ./apps/<name>/package.nix {}`; add this
          # flake's overlay (or set `services.<app>.package`) if you want a custom
          # build. `default` imports all of them; the per-app modules are
          # exposed too.
          nixosModules = {
            default = ./nix/modules;
            kait2en-kernel = ./nix/modules/kait2en-kernel;
            brcm-firmware = ./nix/modules/brcm-firmware;
            t2-fan-control = ./nix/modules/t2-fan-control;
            t2-smc-control = ./nix/modules/t2-smc-control;
            t2-touchbar = ./nix/modules/t2-touchbar;
            t2bce-audio-dsp = ./nix/modules/t2bce-audio-dsp;
            kait2en-suspend = ./nix/modules/kait2en-suspend;
            kait2en-rtc-sync = ./nix/modules/kait2en-rtc-sync;
            # Shared bridge-link integration + t2-ave + t2-touchid.
            t2-services = ./nix/modules/t2-services;
            t2-power-explorer = ./nix/modules/t2-power-explorer;
            t2-power-tune = ./nix/modules/t2-power-tune;
            t2-zone-power = ./nix/modules/t2-zone-power;
            t2-force-click = ./nix/modules/t2-force-click;
            t2-gpu-control = ./nix/modules/t2-gpu-control;
          };

          # Per-device profiles: each imports the aggregate modules and switches
          # on that specific T2 Mac model's settings (currently the audio DSP
          # graph from t2bce-audio-dsp). Import the one matching your machine,
          # e.g. `imports = [ inputs.kait2en.nixosProfiles.macbookpro16-1 ];`.
          nixosProfiles = {
            macbookpro16-1 = ./nix/profiles/macbookpro16-1.nix;
            macbookpro16-4 = ./nix/profiles/macbookpro16-4.nix;
            macbookair9-1 = ./nix/profiles/macbookair9-1.nix;
          };

          # The per-profile build-gate systems (see `checkConfigurations` above).
          nixosConfigurations = checkConfigurations;

          # An overlay exposing the apps under pkgs (modules need an explicit
          # kernel, so they stay behind `self.lib.<system>.kernelModulesFor`).
          # The brcm-firmware builder is exposed too; it takes a macOS `version`,
          # so `brcm-firmware` defaults to sonoma and `brcm-firmwareFor` lets you
          # pick another (monterey/ventura/sonoma).
          overlays.default = final: _prev: {
            kait2en = (final.callPackage ./apps { }) // {
              kernelModulesFor = kernel: final.callPackage ./modules { inherit kernel; };
              # The ALSA UCM2 tree carrying the Apple T2 split-channel profiles
              # (stock alsa-ucm-conf + our AppleT2 use cases); the t2bce-audio-dsp
              # NixOS module points ALSA_CONFIG_UCM2 at it.
              t2bce_audio-alsa-ucm-conf = final.callPackage ./nix/pkgs/t2bce_audio-alsa-ucm-conf { };
              # The Fedora-matched base kernel + the SPI-HID ABI patch the T2
              # HID modules need (see nix/pkgs/kernel for the selection policy).
              # Applied directly (not callPackage) so the kernel's own chainable
              # `.override` survives for linuxPackagesFor/boot.kernelPackages.
              kernel = import ./nix/pkgs/kernel { pkgs = final; };
              brcm-firmwareFor = version: final.callPackage ./nix/pkgs/brcm-firmware { inherit version; };
              brcm-firmware = final.callPackage ./nix/pkgs/brcm-firmware { version = "sonoma"; };
            };
          };
        };

        # Per-system outputs (packages, checks, formatter).
        perSystem =
          { pkgs, lib, ... }:
          let
            # `callPackage` decorates its result with `override`/
            # `overrideDerivation`; strip them so only real packages surface.
            stripCallPackage =
              set:
              removeAttrs set [
                "override"
                "overrideDerivation"
              ];
            # The KaiT2en kernel: the Fedora-matched base kernel + the SPI-HID
            # ABI patch the out-of-tree T2 HID drivers compile against (see
            # nix/pkgs/kernel for the selection policy and single bump site).
            # Applied directly (not callPackage) so the kernel's own chainable
            # `.override` survives for linuxPackagesFor/boot.kernelPackages.
            kait2enKernel = import ./nix/pkgs/kernel { inherit pkgs; };
            # Modules built against the KaiT2en kernel, so each is buildable on
            # its own from the flake and the HID drivers find the SPI-HID
            # symbols.
            kernelModules = stripCallPackage (pkgs.callPackage ./modules { kernel = kait2enKernel; });
            apps = stripCallPackage (pkgs.callPackage ./apps { });
            audioUcmConf = pkgs.callPackage ./nix/pkgs/t2bce_audio-alsa-ucm-conf { };
            allPackages =
              kernelModules
              // apps
              // {
                # The patched KaiT2en kernel (Fedora-matched base + SPI-HID ABI patch).
                kernel = kait2enKernel;
                inherit audioUcmConf;
                # amdgpu + the gpu-runtime-pm series (hardware.kait2en.gpuRuntimePm).
                gpu-runtime-pm = pkgs.callPackage ./nix/pkgs/gpu-runtime-pm { kernel = kait2enKernel; };
                t2bce_audio-alsa-ucm-conf = audioUcmConf;
              };
          in
          {
            # The automatic Wi-Fi/Bluetooth firmware is deliberately *not* a
            # `packages` output: it is unfree, so listing it here would make
            # `nix flake check` fail without allowUnfree. Reach it instead through
            # the overlay (`pkgs.kait2en.brcm-firmware`) or the
            # `hardware.kait2en.firmware` NixOS module.
            packages = allPackages;

            # The complete build gate: every package (kernel included) plus the
            # per-profile NixOS toplevels. `nix flake check` therefore proves the
            # whole stack builds — this is the gate the upstream-sync skill
            # (.agents/skills/sync-upstream/SKILL.md) and CI rely on. Keeping it
            # derived from `allPackages`/`checkConfigurations` means new packages
            # and profiles are gated automatically; nothing to remember.
            checks =
              allPackages
              // lib.mapAttrs' (
                name: system: lib.nameValuePair "nixos-${name}" system.config.system.build.toplevel
              ) checkConfigurations;

            formatter = pkgs.nixfmt-tree;
          };
      }
    );
}
