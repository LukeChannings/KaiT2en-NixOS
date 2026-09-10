# NixOS module for t2-power-explorer.
#
# The app is a plain GTK GUI plus one privileged status helper it calls via
# pkexec. Its only system integration is the polkit action shipped in the
# package's share/polkit-1/actions, which NixOS collects once the package is in
# environment.systemPackages. The status action is allow_active=yes (no
# password), and the helper only reads sysfs/PCI config space, so there is no
# kernel `msr` module requirement.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-power-explorer;
in
{
  options.services.t2-power-explorer = {
    enable = lib.mkEnableOption "the T2 power/device-topology explorer GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-power-explorer/package.nix {
        branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
      };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-power-explorer/package.nix { }";
      description = "The t2-power-explorer package (GUI, helper and polkit policy).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
