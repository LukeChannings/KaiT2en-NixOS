# Source for one t2-services/ Rust crate.
#
# Upstream's t2-services/ crates (t2-ave, t2-journal, t2-touchid) take the
# shared bridgeOS transport as a relative path dependency
# (`../shared/protocols/t2-bridgexpc`), so a crate's own directory is not a
# self-contained source. This returns the t2-services tree filtered to the
# named crate + shared/; build it with `cargoRoot`/`buildAndTestSubdir` set to
# the crate name. Filtering keeps unrelated sibling edits from rebuilding it.
{ lib }:

crate:
let
  root = ../../t2-services;
  keep = [
    crate
    "shared"
  ];
in
lib.cleanSourceWith {
  name = "${crate}-source";
  src = lib.cleanSource root;
  filter =
    path: _type:
    let
      rel = lib.removePrefix (toString root + "/") (toString path);
    in
    lib.elem (lib.head (lib.splitString "/" rel)) keep;
}
