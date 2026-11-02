# NixOS module for t2-debug.
#
# Installs the T2 bridgeOS debugger GUI (`t2-debug`) and CLI (`t2debug`) and
# lists the GUI in the KaiT2en app folder. Upstream ships no unit, policy or
# udev rule for it (install-apps.sh just `make install`s it on every T2 Mac).
# It talks to bridgeOS over the shared NCM link, so services.t2-services comes
# with it.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-debug;
  branding = pkgs.callPackage ../../pkgs/kait2en-branding { };
in
{
  options.services.t2-debug = {
    enable = lib.mkEnableOption "the T2 bridgeOS debugger, `t2-debug` / `t2debug`";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../apps/t2-debug/package.nix { inherit branding; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../apps/t2-debug/package.nix { }";
      description = "The t2-debug package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.kait2en-utilities.apps = [ "org.t2debug.gtk.desktop" ];
    services.t2-services.enable = lib.mkDefault true;
  };
}
