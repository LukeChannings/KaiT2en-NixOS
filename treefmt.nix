# Formatter/linter set for this fork.
#
# SCOPE: this repo is a purely additive fork of KaiT2en-Fedora — every file
# that is not a `.nix` file, this `Justfile`, or a `*.yaml` workflow belongs to
# upstream and arrives here through merges. Reformatting upstream's ~67 shell
# scripts or its `.github/workflows/*.yml` would turn every future sync into a
# conflict, so the formatters are scoped to what this fork actually owns:
#
#   *.nix    — all 47 are ours (nixfmt, deadnix, statix)
#   Justfile — ours
#   *.yaml   — ours; upstream's YAML is uniformly `.yml`, which makes the
#              extension an exact discriminator. Our workflows use `.yaml`.
#
# shfmt is deliberately absent: there is no shell script in this tree that
# this fork owns. Add it (and drop this note) if that ever changes.
{ lib, pkgs, ... }:
{
  projectRootFile = "flake.nix";

  # No `checks.treefmt`. That check formats a *store copy* of `projectRoot`
  # (= `self`), and because this repo is evaluated through the flake-compat
  # shim with `copySourceTreeToStore = false`, `self` is the working directory
  # verbatim — gitignored output and all. Copying it in means dragging the
  # kernel source pool and every Rust `target/` into the store, which is both
  # enormous and outright broken (cargo's `incremental/*.lock` files are
  # unreadable, so the copy fails).
  #
  # Linting is `just lint` instead: treefmt over the live tree, no store copy.
  # That is what the Lint workflow runs, so CI coverage is unchanged — and it
  # keeps the build gate (`just test`) to things that actually build.
  flakeCheck = false;

  programs.nixfmt.enable = true;
  programs.deadnix.enable = true;
  programs.statix.enable = true;
  # `nix-build -A` only auto-calls a `{ ... }:` default.nix, not `_:`.
  programs.statix.disabled-lints = [ "empty_pattern" ];
  programs.just.enable = true;

  programs.yamllint.enable = true;
  settings.formatter.yamllint.includes = lib.mkForce [ "*.yaml" ];

  programs.actionlint.enable = true;
  settings.formatter.actionlint.includes = lib.mkForce [
    ".forgejo/workflows/*.yaml"
    ".github/workflows/*.yaml"
  ];
  # actionlint only discovers a config by itself when `.github/workflows/`
  # exists, and would then read `.github/actionlint.yaml`; point it at the
  # Forgejo one explicitly (runner labels + the full-URL `uses:` ignore).
  settings.formatter.actionlint.options = [
    "-config-file"
    ".forgejo/actionlint.yaml"
  ];

  settings.formatter.forgejo-schema = {
    command = lib.getExe (
      pkgs.writeShellApplication {
        name = "forgejo-schema-validate";
        runtimeInputs = [ pkgs.forgejo-runner ];
        text = ''
          for f in "$@"; do
            case "$f" in
              */action.yaml | */action.yml)
                forgejo-runner validate --action --path "$f" ;;
              *)
                forgejo-runner validate --workflow --path "$f" ;;
            esac
          done
        '';
      }
    );
    includes = [
      ".forgejo/workflows/*.yaml"
      ".forgejo/workflows/*.yml"
      ".forgejo/**/action.yaml"
      ".forgejo/**/action.yml"
    ];
  };
}
