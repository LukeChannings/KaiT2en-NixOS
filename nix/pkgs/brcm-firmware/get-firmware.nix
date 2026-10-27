{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
}:

stdenvNoCC.mkDerivation {
  name = "get-firmware";

  src = fetchFromGitHub {
    owner = "AsahiLinux";
    repo = "asahi-installer";
    # Do not pin back below v0.9.0 without re-reading these two, both of which
    # fail SILENTLY or at random rather than loudly:
    #   * aeb5600 (v0.8.1) replaced wifi.py's `dirpath.lstrip(source_path)` with
    #     os.path.relpath. str.lstrip takes a set of CHARACTERS, not a prefix, so
    #     any source path containing a capital C ate the leading C of the
    #     C-4364__s-B3 chip directories and tripped `assert not props`. With the
    #     `mktemp -d` path this package used to pass, that was a ~15% coin flip
    #     per build.
    #   * bluetooth.py's VENDORMAP gained "AMKOR" (Apple ships AMKOR-packaged
    #     parts now). Files whose vendor will not resolve are skipped, so on
    #     v0.7.9 every AMKOR Bluetooth blob was dropped from the output with only
    #     an "Unable to determine vendor" line to show for it.
    rev = "v0.9.2";
    hash = "sha256-q+J3/q7SP9KSkoyrL9uvI4wGls/16CUXxMFcUaz+ytM=";
  };

  # Turns the two collectors into standalone scripts: drops the package-relative
  # imports, inlines FWFile, writes the firmware out directly (hard-linking
  # duplicates) instead of building an FWPackage, and restricts the walk to the
  # four T2 chip directories. Regenerate by replaying it on a scratch checkout of
  # `src` rather than hand-editing the hunk offsets.
  patches = [ ./get-firmware-standalone.patch ];

  buildInputs = [ python3 ];

  installPhase = ''
    cd asahi_firmware
    install -Dm755 bluetooth.py $out/bin/get-bluetooth
    install -Dm755 wifi.py $out/bin/get-wifi
  '';

  meta = {
    description = "Patched Asahi Linux Installer scripts to get brcm firmware";
    homepage = "https://github.com/AsahiLinux/asahi-installer";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
