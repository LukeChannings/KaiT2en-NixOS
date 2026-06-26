# flake-compat shim: lets non-flake Nix (`nix-build`, `nix-shell`, plain
# `import ./.`) evaluate the flake in ./flake.nix. The flake's outputs
# (packages, lib, overlays) are reachable on the returned attrset, e.g.
#
#   nix-build -A packages.x86_64-linux.t2smc
#   (import ./.).packages.x86_64-linux.t2-fan-control
#
# flake-compat is pinned by the flake.lock entry, fetched read-only from the
# lock's locked url/narHash so this evaluates without network access once the
# lock is materialised.
let
  lockFile = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compat-node = lockFile.nodes.${lockFile.nodes.root.inputs.flake-compat};
  flake-compat = fetchTarball {
    inherit (flake-compat-node.locked) url;
    sha256 = flake-compat-node.locked.narHash;
  };

  flake = import flake-compat {
    # Pass `src` as an attrset that already carries `outPath` so flake-compat
    # copies nothing into the store (outPath stays this directory).
    src = {
      outPath = ./.;
    };
  };
in
flake.defaultNix
