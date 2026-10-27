# Wi-Fi and Bluetooth firmware for T2 Macs, extracted automatically from a macOS
# recovery image. This is the declarative alternative to copying the blobs out
# of an installed macOS by hand: fetchmacos.nix downloads a recovery BaseSystem
# image for the chosen macOS version, and this derivation mounts it inside a
# throwaway Linux VM (vmTools.runInLinuxVM — needed for the loop + hfsplus
# mounts) and runs the patched Asahi get-bluetooth / get-wifi scripts over
# /usr/share/firmware to collect the brcm blobs.
#
# Ported from nixos-hardware's apple/t2 brcm-firmware package. Consume it via
# `hardware.firmware` (see nix/modules/brcm-firmware).
{
  lib,
  stdenvNoCC,
  callPackage,
  vmTools,
  util-linux,
  linux,
  kmod,
  version,
}:

let
  get-firmware = callPackage ./get-firmware.nix { };
  fetchmacos = callPackage ./fetchmacos.nix { };

  # See https://github.com/kholia/OSX-KVM/blob/master/fetch-macOS-v2.py#L534-L546.
  # Versions before macOS Monterey don't have Bluetooth firmware.
  # Whereas macOS Sequoia doesn't have firmware for MacBook Air 2018 and 2019.
  boards = {
    monterey = {
      boardId = "Mac-B809C3757DA9BB8D";
      mlb = "00000000000000000";
      osType = "latest";
      hash = "sha256-My8FLnqHZn+THfGPIhTSApW/kIWM0ZZhjBxWujhhWPM=";
    };
    ventura = {
      boardId = "Mac-4B682C642B45593E";
      mlb = "00000000000000000";
      osType = "latest";
      hash = "sha256-Qy9Whu8pqHo+m6wHnCIqURAR53LYQKc0r87g9eHgnS4=";
    };
    sonoma = {
      boardId = "Mac-827FAC58A8FDFA22";
      mlb = "00000000000000000";
      osType = "default";
      hash = "sha256-phlpwNTYhugqX2KGljqxpbfGtCFDgggQPzB7U29XSmM=";
    };
    # macOS 26, the last Intel release, and the newest Wi-Fi firmware a T2 Mac
    # can be given: 9.30.514.0.32.5.94 on BCM4364B3 against sonoma's
    # 9.30.503.0.32.5.92. Tahoe has DROPPED the Wi-Fi firmware for brcmfmac4355c1
    # (MacBookPro15,x) and brcmfmac4377b3 (MacBookPro16,2/16,3) - only the
    # brcmbt4377b3 Bluetooth pair survives, which is no use without Wi-Fi. Hence
    # an option, not the default.
    #
    # Unlike the entries above this one cannot be pinned by board: `default`
    # yields the OS the machine shipped with (Catalina here), and no Intel Mac
    # ever shipped with Tahoe, so only `latest` reaches it. `latest` tracks
    # Apple, so a 26.x recovery refresh will break this hash; the fix is to
    # re-pin it. macrecovery's -os takes only {default,latest}, so there is no
    # way to name the build (currently 140-93589).
    tahoe = {
      boardId = "Mac-E1008331FDC96864"; # MacBookPro16,1
      mlb = "00000000000000000";
      osType = "latest";
      hash = "sha256-kLDFAF1oc5BEazLsAFYxdaq+TO5nyTdWT3DBAZyXm8Q=";
    };
  };
in

vmTools.runInLinuxVM (
  stdenvNoCC.mkDerivation {
    pname = "brcm-firmware";
    inherit version;

    src = fetchmacos {
      name = version;
      inherit (boards.${version})
        boardId
        mlb
        osType
        hash
        ;
    };
    dontUnpack = true;

    nativeBuildInputs = [
      util-linux
      get-firmware
    ];
    buildPhase = ''
      ln -s ${linux}/lib /lib
      ${kmod}/bin/modprobe loop
      ${kmod}/bin/modprobe hfsplus

      # Deterministic, not mktemp: get-wifi derives each firmware file's identity
      # from its path relative to this directory, so a random name makes the
      # parse (and historically, the build) depend on the draw. We are alone in
      # a throwaway VM, so there is nothing to collide with.
      imgdir=/tmp/img
      mkdir -p $imgdir
      loopdev=$(losetup -f | cut -d "/" -f 3)
      losetup -P $loopdev $src
      loopdev_partition=/dev/$(lsblk -o KNAME,TYPE,MOUNTPOINT -n | grep $loopdev | tail -1 | awk '{print $1}')
      mount $loopdev_partition $imgdir

      get-bluetooth $imgdir/usr/share/firmware/bluetooth bluetooth/
      get-wifi $imgdir/usr/share/firmware/wifi wifi/
    '';

    installPhase = ''
      mkdir -p $out/lib/firmware/brcm
      cp bluetooth/brcm/* $out/lib/firmware/brcm/
      cp wifi/brcm/* $out/lib/firmware/brcm/
    '';

    meta = {
      description = "Wi-Fi and Bluetooth firmware for T2 Macs";
      license = lib.licenses.unfree;
      platforms = lib.platforms.linux;
    };
  }
)
