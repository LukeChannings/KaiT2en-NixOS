# NixOS module for the KaiT2en suspend/resume hardware fixes.
#
# Upstream ships systemd/kait2en-suspend.service, a oneshot bound to
# sleep.target that runs scripts/fedora/kait2en-suspend.sh:
#   * pre  (ExecStart, before sleep): unload modules that wedge suspend on
#     certain T2 Macs — amdgpu on the dGPU MacBookPros, and the BCM4377
#     Wi-Fi/BT stack (hci_bcm4377 + brcmfmac{,_wcc}).
#   * post (ExecStop,  after resume): reload exactly the modules it unloaded,
#     tracked via marker files under /run/kait2en-suspend.
#
# The script shells out to `modprobe`/`modprobe -r`, so this module packages it
# with kmod + coreutils on PATH and reproduces the unit natively. The upstream
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
    systemd.services.kait2en-suspend = {
      description = "Kait2en T2 suspend and resume hardware fixes";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      unitConfig.StopWhenUnneeded = true;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${cfg.package}/bin/kait2en-suspend pre";
        ExecStop = "${cfg.package}/bin/kait2en-suspend post";
        # The helper records which modules it unloaded under here.
        RuntimeDirectory = "kait2en-suspend";
        RuntimeDirectoryPreserve = true;
      };
    };
  };
}
