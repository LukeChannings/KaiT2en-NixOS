# NixOS module for the internal Apple T2 CDC-NCM debug network interface.
#
# Every T2 Mac exposes a USB CDC-NCM function from the T2 controller (Apple
# 05ac:8233) that shows up as an extra Ethernet interface. It is a bridgeOS
# debug link, not a real NIC: left to its own devices NetworkManager tries to
# manage it, which confuses routing and clutters the network UI.
#
# Upstream (Fedora) handles this with a single udev rule
# (scripts/fedora/install-networkmanager-rules.sh writes
# 90-kait2en-t2-network.rules) that renames the function to `t2_ncm` and marks
# it NM-unmanaged.
#
# The old `kait2en-t2-ncm-down` oneshot that held the interface
# administratively down was retired upstream (commit "remove t2-ncm services"):
# `NM_UNMANAGED=1` is enough, so the helper script and its systemd unit were
# deleted. This module follows suit — it now only ships the udev rule.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.t2-ncm;

  # Renames the T2 CDC-NCM function to t2_ncm and hides it from NetworkManager.
  # Matched on USB vendor/model + driver (not MAC or name, which vary between
  # machines and naming-scheme versions), exactly as the Fedora installer's
  # 90-kait2en-t2-network.rules does. The rename emits a move event, so the
  # NM_UNMANAGED property is re-applied on change|move too.
  ncmUdevRules = pkgs.writeTextDir "lib/udev/rules.d/90-kait2en-t2-network.rules" ''
    # Apple T2 internal CDC-NCM interface.
    #
    # Do not match by MAC address or interface name:
    # both may differ between systems or naming-scheme versions.
    #
    # 05ac:8233 = Apple T2 Controller
    # cdc_ncm   = internal USB CDC-NCM network function
    ACTION=="add", SUBSYSTEM=="net", ENV{ID_BUS}=="usb", ENV{ID_VENDOR_ID}=="05ac", ENV{ID_MODEL_ID}=="8233", DRIVERS=="cdc_ncm", NAME:="t2_ncm", ENV{NM_UNMANAGED}="1"
    # Renaming eth0 to t2_ncm emits a move event; retain the final properties.
    ACTION=="change|move", SUBSYSTEM=="net", KERNEL=="t2_ncm", ENV{NM_UNMANAGED}="1"
  '';
in
{
  options.services.t2-ncm = {
    enable = lib.mkEnableOption ''
      management of the internal Apple T2 CDC-NCM debug network interface:
      rename it to `t2_ncm` and keep it out of NetworkManager'';
  };

  config = lib.mkIf cfg.enable {
    # The udev rule renames the interface and marks it NM_UNMANAGED. That is
    # sufficient on its own; the old administrative-down oneshot was retired
    # upstream.
    services.udev.packages = [ ncmUdevRules ];
  };
}
