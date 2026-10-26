# T2 Macs are Intel, so everything this repo builds is x86_64-linux and the
# recipes below target it explicitly. That is deliberately not
# `builtins.currentSystem`: a host that is not itself x86_64-linux can still
# build these, because Nix routes the derivations to whatever builder can
# take them — the fleet's Macs run a nixham linux-builder offering
# x86_64-linux through Rosetta, which is how the forge's `snowman` runner
# builds this repo from macOS.
system := "x86_64-linux"

# List available recipes
default:
    @just --list

# Format the tree
format:
    treefmt

alias fmt := format

# The flake's checks.treefmt output exists for CI, where a store copy
# is acceptable; day to day, lint the live tree instead.

# Lint the working tree directly (no store copy)
lint:
    treefmt --ci

# Build package ATTR; with no argument, the default package (the KaiT2en
# kernel).
build attr="default":
    nix-build -A packages.{{ system }}.{{ attr }}

# There is deliberately no `build-all`: the gate below (`just test`) builds
# every package *and* the per-profile NixOS toplevels, so it is a strict
# superset, and each of these runs costs hours of kernel build.

# The complete build gate: every package plus the three per-profile NixOS
# toplevels — i.e. the flake's `checks`. Proves the whole stack still builds
# (patched kernel, every out-of-tree module, every app, the module wiring).
# This is what CI runs.
#
# Builds with --keep-going and links every realised output as ./result-N, so
# one broken target does not throw away the rest: CI's cache push still gets
# the multi-hour kernel, and the fix-up run substitutes it instead of
# rebuilding. The recipe still exits non-zero, so the gate itself fails.
#
# The kernel's build-time-only `dev` output is picked up here too (no
# toplevel closure carries it, but consumers building their own out-of-tree
# modules need it).
test:
    #!/usr/bin/env bash
    set -uo pipefail

    echo "build gate: {{ system }} (host $(nix-instantiate --eval --expr builtins.currentSystem | tr -d '"'))"
    rm -f result result-*

    # Instantiate separately from building, so that an evaluation failure is
    # never mistaken for "nothing to build". An earlier version of this
    # recipe conflated the two and reported a green gate having built
    # nothing, so both outcomes below are hard errors.
    drvfile="$(mktemp)"
    trap 'rm -f "$drvfile"' EXIT
    if ! nix-instantiate -E \
      'builtins.attrValues (import ./. { }).checks.{{ system }}' \
      > "$drvfile"; then
      echo "error: evaluating the build gate failed" >&2
      exit 1
    fi
    readarray -t drvs < "$drvfile"
    if [ "${#drvs[@]}" -eq 0 ]; then
      echo "error: the build gate evaluated to zero derivations" >&2
      exit 1
    fi
    echo "gate: ${#drvs[@]} derivation(s)"

    rc=0
    nix-build --keep-going --no-out-link "${drvs[@]}" > /dev/null || rc=$?
    i=0
    for drv in "${drvs[@]}"; do
      while read -r out; do
        if nix-store --check-validity "$out" 2> /dev/null; then
          ln -sfn "$out" "result-$i"
          i=$((i + 1))
        fi
      done < <(nix-store --query --outputs "$drv")
    done
    echo "realised $i output(s) -> ./result-*"
    exit $rc

# Create a worktree at .worktrees/<issue>-<slug> on a matching branch, then prime it
worktree issue slug:
    git worktree add .worktrees/{{ issue }}-{{ slug }} -b {{ issue }}-{{ slug }}
    just init-worktree .worktrees/{{ issue }}-{{ slug }}

# Copies .env from the main worktree (gitignored, so absent in fresh
# worktrees), then direnv allow + reload. Zed runs this automatically via
# its create_worktree hook (see .zed/tasks.json).

# Prime a freshly created worktree (or any new checkout)
init-worktree dir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    main="$(git worktree list --porcelain | head -1 | cut -d' ' -f2-)"
    if [ -f "$main/.env" ] && [ ! -e "{{ dir }}/.env" ]; then
      cp "$main/.env" "{{ dir }}/.env"
    fi
    cd "{{ dir }}" && direnv allow && direnv reload
