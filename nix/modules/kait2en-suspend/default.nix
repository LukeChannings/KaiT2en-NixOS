# NixOS module for the KaiT2en suspend/resume hardware fixes.
#
# Upstream writes kait2en-suspend.service inline from
# scripts/fedora/install-suspend-service.sh (the old systemd/ directory is
# gone): a oneshot bound to sleep.target, ordered after NetworkManager and
# t2-services-suspend, that runs scripts/fedora/kait2en-suspend.sh:
#   * pre  (ExecStart, before sleep): unload drivers that wedge S3 — now only
#     brcmfmac{,_wcc} on BCM4350 machines (MacBookPro14,1). The BCM4377
#     Wi-Fi/BT stack used to be unloaded too; upstream dropped that once the
#     runtime wireless series (hardware.kait2en.wireless: PCIe state before
#     D0_INFORM, probing again after a resume through firmware) let it
#     suspend in place.
#   * post (ExecStop,  after resume): reload exactly the modules it unloaded,
#     tracked via marker files under /run/kait2en-suspend.
#
# The script shells out to `rmmod`/`modprobe`, so this module packages it with
# kmod + coreutils on PATH and reproduces the unit natively. The upstream
# installer drops the script at /usr/local/libexec/kait2en; here it lives in the
# Nix store and the unit points at that.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.kait2en-suspend;

  # The repo's suspend helper, with its shebang patched to the Nix bash and
  # kmod (modprobe) + coreutils on PATH so it runs outside a Fedora layout.
  suspendScript =
    pkgs.runCommand "kait2en-suspend"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        install -Dm755 ${../../../scripts/fedora/kait2en-suspend.sh} "$out/bin/kait2en-suspend"
        patchShebangs "$out/bin/kait2en-suspend"
        wrapProgram "$out/bin/kait2en-suspend" \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.kmod
              pkgs.coreutils
            ]
          }
      '';
in
{
  options.services.kait2en-suspend = {
    enable = lib.mkEnableOption "the KaiT2en T2 Mac suspend/resume hardware fixes";

    package = lib.mkOption {
      type = lib.types.package;
      default = suspendScript;
      defaultText = lib.literalExpression "a wrapper around scripts/fedora/kait2en-suspend.sh";
      description = ''
        Package providing the `kait2en-suspend` helper (invoked as
        `kait2en-suspend pre` before sleep and `kait2en-suspend post` on resume).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!config.hardware.kait2en.wireless.enable) ''
      services.kait2en-suspend no longer unloads the BCM4377 Wi-Fi/Bluetooth
      drivers around S3: upstream relies on the resume fixes of the patched
      drivers instead. Without hardware.kait2en.wireless the stock brcmfmac
      and hci_bcm4377 may not come back after a resume.
    '';

    systemd.services.kait2en-suspend = {
      description = "Kait2en T2 suspend and resume hardware fixes";
      before = [ "sleep.target" ];
      after = [
        "NetworkManager.service"
        "t2-services-suspend.service"
      ];
      wantedBy = [ "sleep.target" ];
      unitConfig.StopWhenUnneeded = true;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStopSec = 150;
        ExecStart = "${cfg.package}/bin/kait2en-suspend pre";
        ExecStop = "${cfg.package}/bin/kait2en-suspend post";
        # The helper records which modules it unloaded under here.
        RuntimeDirectory = "kait2en-suspend";
        RuntimeDirectoryPreserve = true;
      };
    };
  };
}
