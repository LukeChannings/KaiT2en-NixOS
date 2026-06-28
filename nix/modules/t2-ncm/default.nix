# NixOS module for the internal Apple T2 CDC-NCM debug network interface.
#
# Every T2 Mac exposes a USB CDC-NCM function from the T2 controller (Apple
# 05ac:8233) that shows up as an extra Ethernet interface. It is a bridgeOS
# debug link, not a real NIC: left to its own devices NetworkManager tries to
# manage it, and it flaps "up" on its own, which confuses routing and clutters
# the network UI.
#
# Upstream (Fedora) handles this in two pieces, both ported here:
#   * scripts/fedora/install-networkmanager-rules.sh writes a udev rule that
#     renames the function to `t2_ncm`, marks it NM-unmanaged, and pulls in the
#     down-service whenever it (re)appears.
#   * systemd/kait2en-t2-ncm-down.service + scripts/fedora/kait2en-t2-ncm-down.sh
#     is a oneshot, bound to the device, that holds the interface administratively
#     down (it retries, because the firmware re-raises it for a while after probe).
#
# The Fedora installer drops the helper under /usr/local/libexec/kait2en and the
# rule under /etc/udev/rules.d; here the script lives in the Nix store, the unit
# points at it, and the rule is shipped as a udev package.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-ncm;

  # The repo's down helper, with its shebang patched to the Nix bash and
  # iproute2 (ip) + coreutils (seq/sleep/printf) on PATH so it runs outside a
  # Fedora layout. Same packaging pattern as kait2en-suspend.
  ncmDownScript =
    pkgs.runCommand "kait2en-t2-ncm-down"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        install -Dm755 ${../../../scripts/fedora/kait2en-t2-ncm-down.sh} "$out/bin/kait2en-t2-ncm-down"
        patchShebangs "$out/bin/kait2en-t2-ncm-down"
        wrapProgram "$out/bin/kait2en-t2-ncm-down" \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.iproute2
              pkgs.coreutils
            ]
          }
      '';

  # Renames the T2 CDC-NCM function to t2_ncm, hides it from NetworkManager, and
  # starts the down-service on add/change. Matched on USB vendor/model + driver
  # (not MAC or name, which vary between machines and naming-scheme versions),
  # exactly as the Fedora installer's 90-kait2en-t2-network.rules does.
  ncmUdevRules = pkgs.writeTextDir "lib/udev/rules.d/90-kait2en-t2-network.rules" ''
    # Apple T2 internal CDC-NCM interface.
    #
    # Do not match by MAC address or interface name:
    # both may differ between systems or naming-scheme versions.
    #
    # 05ac:8233 = Apple T2 Controller
    # cdc_ncm   = internal USB CDC-NCM network function
    ACTION=="add", SUBSYSTEM=="net", ENV{ID_BUS}=="usb", ENV{ID_VENDOR_ID}=="05ac", ENV{ID_MODEL_ID}=="8233", DRIVERS=="cdc_ncm", NAME:="t2_ncm", ENV{NM_UNMANAGED}="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="kait2en-t2-ncm-down.service"
    ACTION=="change", SUBSYSTEM=="net", KERNEL=="t2_ncm", ENV{NM_UNMANAGED}="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="kait2en-t2-ncm-down.service"
  '';
in
{
  options.services.t2-ncm = {
    enable = lib.mkEnableOption ''
      management of the internal Apple T2 CDC-NCM debug network interface:
      rename it to `t2_ncm`, keep it out of NetworkManager, and hold it down'';

    package = lib.mkOption {
      type = lib.types.package;
      default = ncmDownScript;
      defaultText = lib.literalExpression "a wrapper around scripts/fedora/kait2en-t2-ncm-down.sh";
      description = ''
        Package providing the `kait2en-t2-ncm-down` helper that holds the
        `t2_ncm` interface administratively down.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The udev rule (rename + NM_UNMANAGED) is what fires SYSTEMD_WANTS for the
    # service below.
    services.udev.packages = [ ncmUdevRules ];

    systemd.services.kait2en-t2-ncm-down = {
      description = "Kait2en T2 CDC-NCM debug interface shutdown";
      # Bound to the device so it stops when the interface goes away and is
      # re-run when udev re-adds it (via SYSTEMD_WANTS in the rule).
      bindsTo = [ "sys-subsystem-net-devices-t2_ncm.device" ];
      after = [
        "sys-subsystem-net-devices-t2_ncm.device"
        "NetworkManager.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/kait2en-t2-ncm-down";
      };
    };
  };
}
