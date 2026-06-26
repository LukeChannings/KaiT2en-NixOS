# Download a macOS recovery BaseSystem image with macrecovery and convert it to
# a raw disk image (fw.img). The firmware blobs are extracted from this image by
# default.nix. Fixed-output: the converted image is content-addressed, so this
# is the one derivation in the firmware path that is allowed network access.
{
  stdenvNoCC,
  callPackage,
  dmg2img,
}:

let
  macrecovery = callPackage ./macrecovery.nix { };
in

{
  name,
  boardId,
  mlb,
  osType,
  hash,
}:

stdenvNoCC.mkDerivation {
  name = name;

  dontUnpack = true;

  nativeBuildInputs = [
    macrecovery
    dmg2img
  ];
  buildPhase = ''
    macrecovery download -o . -b ${boardId} -m ${mlb} -os ${osType}
    dmg2img -s BaseSystem.dmg fw.img
  '';

  installPhase = ''
    cp fw.img $out
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = hash;
}
