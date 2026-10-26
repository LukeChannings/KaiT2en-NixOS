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
# kernel). Only x86_64-linux has packages at all.
build attr="default":
    nix-build -A {{ attr }}

# There is deliberately no `build-all`: the gate below (`just test`) builds
# every package *and* the per-profile NixOS toplevels, so it is a strict
# superset, and each of these runs costs hours of kernel build.

# The complete build gate: every package plus the three per-profile NixOS
# toplevels — i.e. the flake's `checks`. Proves the whole stack still builds
# (patched kernel, every out-of-tree module, every app, the module wiring).
# This is what CI runs and what the sync-upstream skill gates on.
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

    system="$(nix-instantiate --eval --expr builtins.currentSystem | tr -d '"')"
    echo "build gate on: $system"

    # The gate is an x86_64-linux kernel and the modules built against it;
    # `checks` is empty on every other system. Refusing to run there is the
    # point: the first version of this recipe printed "no checks for this
    # system" and exited 0, so a CI runner that was not x86_64-linux reported
    # a green gate having built nothing at all.
    if [ "$system" != "x86_64-linux" ]; then
      echo "error: the build gate targets x86_64-linux, not $system" >&2
      exit 1
    fi

    rm -f result result-*

    # Instantiate separately from building, so that an evaluation failure is
    # never mistaken for "nothing to build".
    drvfile="$(mktemp)"
    trap 'rm -f "$drvfile"' EXIT
    if ! nix-instantiate -E \
      'builtins.attrValues (builtins.getAttr builtins.currentSystem (import ./. { }).checks)' \
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
