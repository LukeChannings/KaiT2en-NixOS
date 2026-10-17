# NixOS module for the KaiT2en SMC RTC sync.
#
# Mirrors kait2en-rtc-sync.service, written inline by
# scripts/fedora/install-rtc-sync.sh: the kernel's NTP RTC writeback never
# reaches t2smc on x86 (it stops at the legacy CMOS clock, which KaiT2en
# initcall-blacklists), so once time is synchronised at boot write it to the
# SMC RTC with `hwclock --systohc --utc`. t2smc itself syncs the RTC before
# suspend and at shutdown.
#
# Upstream waits with `chronyc waitsync 180` after chronyd. NixOS defaults to
# systemd-timesyncd, so without chrony the unit polls timedatectl's
# NTPSynchronized for up to 180 s instead — same "synchronised, then write"
# semantics; nothing is written if sync never happens.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.kait2en-rtc-sync;
  useChrony = config.services.chrony.enable;
  hwclock = "${pkgs.util-linux}/bin/hwclock --systohc --utc";

  waitTimesyncd = pkgs.writeShellScript "kait2en-rtc-sync-wait" ''
    for _ in $(${pkgs.coreutils}/bin/seq 180); do
      if [ "$(${config.systemd.package}/bin/timedatectl show -p NTPSynchronized --value)" = yes ]; then
        exec ${hwclock}
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "time not synchronised after 180 s; leaving the SMC RTC unchanged" >&2
    exit 1
  '';
in
{
  options.services.kait2en-rtc-sync.enable = lib.mkEnableOption "writing the synchronised system time to the T2 SMC RTC at boot";

  config = lib.mkIf cfg.enable {
    systemd.services.kait2en-rtc-sync = {
      description = "Kait2en write system time to the T2 SMC RTC";
      wantedBy = [ "multi-user.target" ];
      after = if useChrony then [ "chronyd.service" ] else [ "systemd-timesyncd.service" ];
      serviceConfig = {
        Type = "exec";
        RemainAfterExit = true;
        TimeoutStartSec = 240;
        ExecStart =
          if useChrony then
            "${pkgs.bash}/bin/sh -c '${config.services.chrony.package}/bin/chronyc waitsync 180 && ${hwclock}'"
          else
            "${waitTimesyncd}";
      };
    };
  };
}
