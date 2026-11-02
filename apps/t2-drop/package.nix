# t2-drop (`t2drop`): AirDrop to and from Apple devices over AWDL. A root
# service, D-Bus activated (org.t2drop), that drives the brcmf_awdl generic
# netlink family of the KaiT2en brcmfmac patch (hardware.kait2en.wireless),
# scans for AirDrop senders over BLE and hands received files to per-user
# agents; `t2drop` is also its CLI.
#
# Upstream's Makefile installs systemd/t2-drop.service (hardcodes
# /usr/local/bin), the system-bus policy dbus/org.t2drop.conf, the activation
# file dbus/org.t2drop.service (Exec=/bin/false, SystemdService=t2-drop.service,
# so it needs no path) and networkmanager/90-t2-drop-awdl.conf. The policy and
# activation file ship here under share/dbus-1 for `services.dbus.packages`;
# the NM drop-in under share/t2-drop; the unit is defined natively by
# nix/modules/t2-drop, which puts the `ip`/`nmcli` it runs on PATH.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "t2-drop";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  postInstall = ''
    install -Dm644 dbus/org.t2drop.conf "$out/share/dbus-1/system.d/org.t2drop.conf"
    install -Dm644 dbus/org.t2drop.service \
      "$out/share/dbus-1/system-services/org.t2drop.service"
    install -Dm644 networkmanager/90-t2-drop-awdl.conf \
      "$out/share/t2-drop/90-t2-drop-awdl.conf"
  '';

  meta = {
    description = "AirDrop to and from Apple devices over AWDL on T2 Macs";
    mainProgram = "t2drop";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
