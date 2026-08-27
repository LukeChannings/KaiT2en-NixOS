{
  description = "KaiT2en — Apple T2 Mac kernel modules and userspace apps, packaged for Nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    flake-compat.url = "https://git.lix.systems/lix-project/flake-compat/archive/main.tar.gz";
    flake-compat.flake = false;
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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

            # The KaiT2en kernel: stock 7.0 + the SPI-HID ABI patch the
            # out-of-tree T2 HID drivers compile against. Build the modules
            # against *this* (e.g. `kernelModulesFor kait2enKernel`).
            #
            # Applied directly (not via callPackage) so the result keeps the
            # *kernel's* own chainable `.override` — callPackage would wrap it
            # in makeOverridable, shadowing that with an override that only
            # takes `linux_7_0`, which breaks `pkgs.linuxPackagesFor` /
            # `boot.kernelPackages` (they call `kernel.override { features,
            # kernelPatches, randstructSeed }`).
            kait2enKernel = import ./nix/pkgs/kernel { inherit (pkgs) linux_7_0; };
          }
        );

        # NixOS modules for the userspace apps' system integration (systemd
        # units, udev rules, group memberships). Each module defaults its
        # package to `pkgs.callPackage ./apps/<name>/package.nix {}`; add this
        # flake's overlay (or set `services.<app>.package`) if you want a custom
        # build. `default` imports all three; the per-app modules are exposed
        # too.
        nixosModules = {
          default = ./nix/modules;
          kait2en-kernel = ./nix/modules/kait2en-kernel;
          brcm-firmware = ./nix/modules/brcm-firmware;
          t2-fan-control = ./nix/modules/t2-fan-control;
          t2-smc-control = ./nix/modules/t2-smc-control;
          react-drm = ./nix/modules/react-drm;
          t2-apple-audio-dsp = ./nix/modules/t2-apple-audio-dsp;
          kait2en-suspend = ./nix/modules/kait2en-suspend;
          t2-ncm = ./nix/modules/t2-ncm;
        };

        # Per-device profiles: each imports the aggregate modules and switches
        # on that specific T2 Mac model's settings (currently the audio DSP
        # graph from t2-apple-audio-dsp). Import the one matching your machine,
        # e.g. `imports = [ inputs.kait2en.nixosProfiles.macbookpro16-1 ];`.
        nixosProfiles = {
          macbookpro16-1 = ./nix/profiles/macbookpro16-1.nix;
          macbookpro16-4 = ./nix/profiles/macbookpro16-4.nix;
          macbookair9-1 = ./nix/profiles/macbookair9-1.nix;
        };

        # An overlay exposing the apps under pkgs (modules need an explicit
        # kernel, so they stay behind `self.lib.<system>.kernelModulesFor`).
        # The brcm-firmware builder is exposed too; it takes a macOS `version`,
        # so `brcm-firmware` defaults to sonoma and `brcm-firmwareFor` lets you
        # pick another (monterey/ventura/sonoma).
        overlays.default = final: _prev: {
          kait2en = (final.callPackage ./apps { }) // {
            kernelModulesFor = kernel: final.callPackage ./modules { inherit kernel; };
            # The ALSA UCM2 tree carrying the Apple T2 split-channel profiles
            # (stock alsa-ucm-conf + our AppleT2 use cases). The
            # t2-apple-audio-dsp NixOS module points ALSA_CONFIG_UCM2 at it.
            t2bce_audio-alsa-ucm-conf = final.callPackage ./nix/pkgs/t2bce_audio-alsa-ucm-conf { };
            # Stock 7.0 + the SPI-HID ABI patch the T2 HID modules need.
            # Applied directly (not callPackage) so the kernel's own chainable
            # `.override` survives for linuxPackagesFor/boot.kernelPackages.
            kernel = import ./nix/pkgs/kernel { inherit (final) linux_7_0; };
            brcm-firmwareFor = version: final.callPackage ./nix/pkgs/brcm-firmware { inherit version; };
            brcm-firmware = final.callPackage ./nix/pkgs/brcm-firmware { version = "sonoma"; };
          };
        };
      };

      # Per-system outputs (packages, formatter).
      perSystem =
        { pkgs, ... }:
        let
          # `callPackage` decorates its result with `override`/
          # `overrideDerivation`; strip them so only real packages surface.
          stripCallPackage =
            set:
            removeAttrs set [
              "override"
              "overrideDerivation"
            ];
          # The KaiT2en kernel: stock 7.0 + the SPI-HID ABI patch the
          # out-of-tree T2 HID drivers compile against.
          # Applied directly (not callPackage) so the kernel's own chainable
          # `.override` survives for linuxPackagesFor/boot.kernelPackages.
          kait2enKernel = import ./nix/pkgs/kernel { inherit (pkgs) linux_7_0; };
          # Modules built against the KaiT2en kernel, so each is buildable on
          # its own from the flake and the HID drivers find the SPI-HID
          # symbols.
          kernelModules = stripCallPackage (pkgs.callPackage ./modules { kernel = kait2enKernel; });
          apps = stripCallPackage (pkgs.callPackage ./apps { });
          audioUcmConf = pkgs.callPackage ./nix/pkgs/t2bce_audio-alsa-ucm-conf { };
        in
        {
          # The automatic Wi-Fi/Bluetooth firmware is deliberately *not* a
          # `packages` output: it is unfree, so listing it here would make
          # `nix flake check` fail without allowUnfree. Reach it instead through
          # the overlay (`pkgs.kait2en.brcm-firmware`) or the
          # `hardware.kait2en.firmware` NixOS module.
          packages =
            kernelModules
            // apps
            // {
              # The patched KaiT2en kernel (stock 7.0 + SPI-HID ABI patch).
              kernel = kait2enKernel;
              inherit audioUcmConf;
              t2bce_audio-alsa-ucm-conf = audioUcmConf;
            };

          formatter = pkgs.nixfmt-rfc-style;
        };
    };
}
