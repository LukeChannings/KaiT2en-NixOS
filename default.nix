# flake-compat shim: lets non-flake Nix (`nix-build`, `nix-shell`, plain
# `import ./.`) evaluate the flake in ./flake.nix. The flake's outputs
# (packages, lib, overlays) are reachable on the returned attrset, and this
# system's packages are merged in on top, so both of these work:
#
#   nix-build -A kernel
#   nix-build -A packages.x86_64-linux.t2-smc-control
#   (import ./. { }).nixosConfigurations.check-macbookpro16-1
#
# The flake exists to pin inputs; building and running go through vanilla
# `nix-build` / `nix-shell` via this shim, because flake commands copy the
# whole source tree to the store on every invocation — expensive in a repo
# carrying a kernel source pool. `copySourceTreeToStore = false` keeps that
# from happening here too.
#
# flake-compat is pinned by the flake.lock entry, fetched read-only from the
# lock's locked url/rev/narHash so this evaluates without network access once
# the lock is materialised. Passing `narHash` matters: without it every
# evaluation announces `fetching git input …`, easily mistaken for the cost of
# the kernel evaluation that follows.
{ ... }:
let
  lockFile = builtins.fromJSON (builtins.readFile ./flake.lock);
  flake-compat-node = lockFile.nodes.${lockFile.nodes.root.inputs.flake-compat};
  flake-compat = fetchGit {
    inherit (flake-compat-node.locked) url rev narHash;
  };

  flake = import flake-compat {
    src = ./.;
    copySourceTreeToStore = false;
    useBuiltinsFetchTree = true;
  };

  system = builtins.currentSystem;
in
# Packages only exist on x86_64-linux (see flake.nix); elsewhere there is
# nothing to merge, but the devShells and other outputs still resolve.
flake.defaultNix // (flake.defaultNix.packages.${system} or { })
