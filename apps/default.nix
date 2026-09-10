# The KaiT2en userspace apps, as plain callPackage derivations.
#
# Normally installed by ../scripts/fedora/install-apps.sh (cargo + make install
# / npm). Here each is a Nix package.
#
# The GUI apps that call a privileged helper via pkexec + polkit share the
# branding wordmark (../nix/pkgs/kait2en-branding) and the polkit path-rewriting
# helper (../nix/lib/kait2en-polkit.nix); branding is passed in explicitly since
# it is not a pkgs attribute.
{ callPackage }:

let
  branding = callPackage ../nix/pkgs/kait2en-branding { };
in
{
  t2-fan-control = callPackage ./t2-fan-control/package.nix { };
  t2-smc-control = callPackage ./t2-smc-control/package.nix { };
  react-drm = callPackage ./react-drm/package.nix { };

  t2-journal = callPackage ./t2-journal/package.nix { };
  t2-power-explorer = callPackage ./t2-power-explorer/package.nix { inherit branding; };
  t2-power-tune = callPackage ./t2-power-tune/package.nix { inherit branding; };
  t2-cpu-control = callPackage ./t2-cpu-control/package.nix { inherit branding; };
  t2-dgpu-control = callPackage ./t2-dgpu-control/package.nix { inherit branding; };
  t2-hybrid-gpu-control = callPackage ./t2-hybrid-gpu-control/package.nix { inherit branding; };
}
