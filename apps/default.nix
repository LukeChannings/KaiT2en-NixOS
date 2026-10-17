# The KaiT2en userspace apps, as plain callPackage derivations.
#
# Normally installed by ../scripts/fedora/install-apps.sh (cargo + make
# install) and ../scripts/fedora/install-{t2-remote,touchid}.sh for the
# t2-services. Here each is a Nix package.
#
# The GUI apps share the branding wordmark (../nix/pkgs/kait2en-branding) and,
# for those calling a privileged helper via pkexec + polkit, the path-rewriting
# helper (../nix/lib/kait2en-polkit.nix); branding is passed in explicitly since
# it is not a pkgs attribute.
{ callPackage }:

let
  branding = callPackage ../nix/pkgs/kait2en-branding { };
in
{
  t2-fan-control = callPackage ./t2-fan-control/package.nix { inherit branding; };
  t2-smc-control = callPackage ./t2-smc-control/package.nix { inherit branding; };
  t2-touchbar = callPackage ./t2-touchbar/package.nix { };
  t2-force-click = callPackage ./t2-force-click/package.nix { inherit branding; };
  t2-zone-power = callPackage ./t2-zone-power/package.nix { inherit branding; };
  t2-power-explorer = callPackage ./t2-power-explorer/package.nix { inherit branding; };
  t2-power-tune = callPackage ./t2-power-tune/package.nix { inherit branding; };
  t2-dgpu-control = callPackage ./t2-dgpu-control/package.nix { inherit branding; };
  t2-hybrid-gpu-control = callPackage ./t2-hybrid-gpu-control/package.nix { inherit branding; };

  # dsp/ (host-side PipeWire/WirePlumber speaker + mic DSP).
  t2-dsp = callPackage ../dsp/package.nix { };

  # t2-services/ (bridgeOS services over the T2 NCM link).
  t2-journal = callPackage ../t2-services/t2-journal/package.nix { };
  t2-ave = callPackage ../t2-services/t2-ave/package.nix { };
  t2-touchid = callPackage ../t2-services/t2-touchid/package.nix { };
}
