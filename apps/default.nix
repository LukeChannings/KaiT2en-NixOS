# The KaiT2en userspace apps, as plain callPackage derivations.
#
# Normally installed by ../scripts/fedora/install-apps.sh (cargo + make install
# / npm). Here each is a Nix package.
{ callPackage }:

{
  t2-fan-control = callPackage ./t2-fan-control/package.nix { };
  t2-smc-control = callPackage ./t2-smc-control/package.nix { };
  react-drm = callPackage ./react-drm/package.nix { };
}
