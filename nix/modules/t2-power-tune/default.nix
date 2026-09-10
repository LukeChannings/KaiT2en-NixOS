# NixOS module for t2-power-tune.
#
# A GTK GUI plus two privileged helpers it calls via pkexec. Its system
# integration is the polkit action shipped in the package's
# share/polkit-1/actions, collected by NixOS once the package is in
# environment.systemPackages. It tunes PCIe ASPM / power-saving sysfs at runtime
# through the helper; there is no persistent unit to define here.
#
# (The helper's optional "persist" path writes a generated unit into
# /etc/systemd/system, which is not the NixOS way — prefer configuring the
# tunables you want declaratively. The interactive/runtime tuning works
# regardless.)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-power-tune;
in
{
  options.services.t2-power-tune = {
    enable = lib.mkEnableOption "the T2 PCIe ASPM / power-saving tuner GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-power-tune/package.nix {
        branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
      };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-power-tune/package.nix { }";
      description = "The t2-power-tune package (GUI, helpers and polkit policy).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
