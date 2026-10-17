---
name: sync-upstream
description: Synchronise this NixOS fork with upstream kaiT2en/KaiT2en-Fedora (remote `super`). Full catch-up merge, mirror-map reconciliation of every upstream change into the Nix layer, divergence-patch audit, Fedora-matched kernel bump, build gate, and a sync PR. Invoke by path from the repo root.
---

# Sync KaiT2en-NixOS with upstream

Synchronise this fork with `super/main` (kaiT2en/KaiT2en-Fedora). One run = one
full catch-up: when it ends, `git rev-list HEAD..super/main` is empty, the
build gate is green, and a PR is open against `main`.

**Philosophy:** `modules/` and `apps/` sources stay **byte-identical to
upstream**. Everything NixOS-specific lives in the Nix layer (`nix/`,
`*/package.nix`, `*/default.nix`, `patches/nixos/`). Divergence policy:
**upstream it > drop it > patch it** — a patch is a last resort and must carry
a drop condition (recorded in its header), re-checked every run.

## Procedure

### 1. Preflight

```sh
git checkout main && git pull
git fetch super
LAST_SYNC=$(git merge-base main super/main)   # record before merging
git rev-list --count main..super/main          # the delta this run lands
git checkout -b sync-$(date +%F)
```

Require a clean tree and a green baseline (`nix flake check` on `main` — CI on
the last main push counts). If the baseline is red, fix that first in a
separate PR; never start a sync from red.

### 2. Recon

Read `git log --oneline $LAST_SYNC..super/main` and
`git diff --stat $LAST_SYNC super/main` **before merging**. You are looking
for structural upheavals: directories renamed/split/deleted under `modules/`
or `apps/`, new top-level dirs, build-system rewrites. If you find one you
cannot resolve confidently in a single merge, chunk: merge up to the commit
*before* the upheaval, land that green, then take the upheaval as its own
chunk. Otherwise proceed with one merge.

### 3. Merge

`git merge super/main`, resolving conflicts by ownership:

| Paths | Resolution |
|---|---|
| `modules/**`, `apps/**` *sources* (not the nix files below), `scripts/`, `systemd/`, `data/`, `packaging/`, `website/`, upstream `.github/**`, `patches/upstream|runtime|archived/**`, docs | **theirs**, unconditionally |
| `flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `.agents/**`, `apps/*/package.nix`, `apps/default.nix`, `modules/default.nix`, `.github/workflows/nix.yml` | **ours** (reconciled via the mirror map, not the merge) |
| anything else | read both sides, decide, and add a mirror-map row so next time it's covered |

Upstream's Fedora workflows stay in-tree but disabled in repo settings —
never delete them (recurring conflicts), never enable them.

### 4. Reconcile via the mirror map

For **every row** in the mirror map (below), run
`git diff $LAST_SYNC super/main -- <upstream sources>`. Non-empty diff → a
mandatory checklist item: read the upstream diff *and* our counterpart, then
either apply the semantic change to the Nix layer or record
"no action — cosmetic" in the PR body. Judge semantics, not bytes: a comment
change or a `/usr/local` path shuffle usually needs nothing; a new
`ExecStartPre`, kernel arg, module name, or state path always does.

Then diff the **whole tree**: any changed path not covered by a map row or
the not-consumed list is an **unmapped upstream change** — classify it (new
row, or explicitly add to not-consumed) before proceeding. Never leave a
path unclassified.

Rules for the recurring cases:

- **New kernel module dir** (`modules/<name>/` with a `dkms.conf`): package it
  in `modules/default.nix` (see `mkSimple` / `buildKernelModule` for the bce
  stack's cross-module pattern), sync the version from `dkms.conf`, and wire
  it into `nix/modules/kait2en-kernel`'s `loadModules` / `initrdModules` as
  upstream's installer does.
- **New app dir** (`apps/<name>/`): write `apps/<name>/package.nix` following
  the sibling conventions (`lib.cleanSource ./.`; `buildRustPackage` +
  `wrapGAppsHook4` for Rust/GTK, `python3Packages` + gobject-introspection for
  Python/GTK, `buildNpmPackage` for node), register it in `apps/default.nix`,
  and if it ships any `.service`, `.policy`, udev rule, or pkexec helper, give
  it a NixOS module under `nix/modules/<name>/` and enable it in the relevant
  profiles.
- **systemd services**: upstream ships `.service` files; we re-define each as
  a **native `systemd.services.*` definition** in the app's NixOS module
  (upstream units hardcode `/usr/local/...` and can't be consumed directly),
  with a header comment naming the upstream unit it mirrors. For every
  changed/new `.service` — *and the helpers its Exec lines run* — read the
  upstream change against our module and reconcile semantically (see
  `nix/modules/t2-cpu-control` for the canonical shape).
- **Runtime paths**: grep every new or changed app for absolute paths
  (`/run/`, `/var/`, `/etc/`, `/usr/local/`, `/usr/share/`). Each must resolve
  on NixOS: `RuntimeDirectory` for `/run/<name>` (e.g. `/run/t2-cpu-control`),
  `systemd.tmpfiles` + a `substituteInPlace` to `/var/lib/<name>` for
  persistent state, store-path substitution for data files.
- **Kernel args**: `packaging/installer/install-kernel-args.sh` is the source
  of truth for upstream's kernel parameters and modprobe blacklists. Its
  model-conditional args map to options (`hardware.kait2en.amdgpuAspm`,
  `acpiOsiOverride`, ...) with per-profile defaults — never a global default,
  the installer probes PCI IDs that Nix eval cannot.

### 5. Audit the divergence register

For each patch in `patches/nixos/` (register below): is its **drop condition**
met? Drop it. Does it still apply (`patch -p1 --dry-run` in the app dir)?
If not, upstream touched the same code — re-evaluate whether the divergence is
still needed before rebasing it. Update the register. The ideal count is zero.

### 6. Kernel

Policy: the base kernel **matches the series Fedora stable ships** (what
upstream targets). Query it:

```sh
curl -s 'https://bodhi.fedoraproject.org/updates/?packages=kernel&status=stable&rows_per_page=1' | jq -r '.updates[0].version'
```

If Fedora moved to a new series and the merged module sources support it
(upstream lands compat commits before Fedora ships):
`nix flake update nixpkgs`, bump the single `baseKernel` line in
`nix/pkgs/kernel/default.nix`, and **re-check the SPI-HID ABI patch** against
the new kernel's `include/linux/hid.h` (drop it if `HID_SPI_DEVICE` went
in-tree; rebase if the hunk drifted). If the gate then fails on the new
kernel, hold the kernel back one series (keep the nixpkgs bump), and record
the blocker under Known blockers. Kernel changes are their own commit.

### 7. Gate

```sh
nix fmt
nix flake check -L
```

The checks output is the complete gate: every package (kernel included) and
the three per-profile NixOS toplevels. Fix forward until green. Checks derive
from the package set and `checkConfigurations` in `flake.nix` — new packages
and profiles are gated automatically, but a new *profile* must be added to
`checkConfigurations`.

### 8. Land

Commit series: the merge commit first, then **one commit per reconciled
area** (module packaging, each new app + its module, kernel-arg sync, service
reconciliations, kernel bump). Updates to this file (mirror map, divergence
register, known blockers) belong in the same series. Push and open a PR
against `main` (`gh pr create`) whose body contains:

1. The delta (`LAST_SYNC..super/main` summary) and per-row reconciliation
   outcomes, including the "no action — cosmetic" entries.
2. Divergence register changes (dropped/rebased/added patches).
3. The kernel decision and why.
4. The **hardware smoke checklist** — the merger runs it on a T2 machine
   before merging: boot; Touch Bar (react-drm); internal keyboard + trackpad;
   speakers *and* headphone jack; Wi-Fi/BT; **suspend/resume twice** (the
   historical failure mode); fan + SMC apps; charge-limit and CPU-settings
   persistence across reboot. Add items for whatever this sync touched.

CI builds the PR and pushes to `nix.channings.me`, so the smoke-test machine
substitutes instead of building. **Done** = empty `HEAD..super/main`, green
gate, open PR. Do not merge it yourself — the hardware gate is the user's.

## Mirror map

Every upstream artifact we consume and its NixOS counterpart. Reconcile each
row in step 4; keep this table current — an upstream change with no row and
no not-consumed entry is a policy violation.

### Kernel modules → `modules/default.nix` attrs + `nix/modules/kait2en-kernel` lists

| Upstream sources | Ours |
|---|---|
| `modules/t2bce_core`, `t2bce_dma`, `t2bce_vhci`, `t2bce_audio`, `t2bce_stack` | single `t2bce` derivation (core→dma→vhci→audio build order via upstream's `t2bce_stack`) |
| `modules/t2smc` | `t2smc` |
| `modules/t2bdrm` | `t2bdrm` |
| `modules/t2gmux` | `t2gmux` |
| `modules/t2smp` | `t2smp` (pairs with upstream's early-CPU-offlining patch; see Known blockers) |
| `modules/t2mfi_fastcharge` | `t2mfi_fastcharge` |
| `modules/hid_t2magicmouse` | `hid_t2magicmouse` (needs the SPI-HID ABI kernel patch) |
| `modules/t2touchbar` | `t2touchbar` (`t2hid`, `t2touchbar_bl`, `t2touchbar_kbd`) |
| `modules/t2thunderbolt` | `t2thunderbolt` |
| `modules/apfs` | **dropped, following upstream** — point users at nixpkgs' apfs |

Version bumps in any `dkms.conf` must land in the matching derivation.

### Audio

| Upstream sources | Ours |
|---|---|
| `modules/t2bce_audio-dsp/firs/<model>` (graphs, FIRs), its udev/WirePlumber payload | `nix/modules/t2bce-audio-dsp` (reads the firs tree directly, rewrites FIR paths to the store, generates the WirePlumber drop-in, patches PipeWire with the kekrby ACP profile-sets) |
| `modules/t2bce_audio-alsa-ucm-conf/ucm2` | `nix/pkgs/t2bce_audio-alsa-ucm-conf` |

New `firs/<model>` dirs → extend the module's `model` enum + consider a new
profile.

### Apps → `apps/<name>/package.nix` + NixOS module

| Upstream sources (incl. their `.service`/`.policy`/udev/helpers) | Ours |
|---|---|
| `apps/react-drm` | `package.nix` + `nix/modules/react-drm` + divergence patch (register) |
| `apps/t2-fan-control` | `package.nix` + `nix/modules/t2-fan-control` + divergence patch (register) |
| `apps/t2-smc-control` | `package.nix` + `nix/modules/t2-smc-control` |
| `apps/t2-cpu-control` | `package.nix` + `nix/modules/t2-cpu-control` (`/run/t2-cpu-control` = RuntimeDirectory; state patched to `/var/lib/t2-cpu-control`) |
| `apps/t2-power-tune` | `package.nix` + `nix/modules/t2-power-tune` |
| `apps/t2-power-explorer` | `package.nix` + `nix/modules/t2-power-explorer` |
| `apps/t2-dgpu-control`, `apps/t2-hybrid-gpu-control` | `package.nix` each + shared `nix/modules/t2-gpu-control` (`gpuControl.mode = "dgpu" | "hybrid"`) |
| `apps/t2-journal` | `package.nix` only (CLI, no system integration) |
| `apps/t2-kernel-builder` | **not ported** — Fedora COPR tooling; our kernel comes from nixpkgs |

### System integration

| Upstream sources | Ours |
|---|---|
| `systemd/kait2en-suspend.service` + `scripts/fedora/kait2en-suspend.sh` | `nix/modules/kait2en-suspend` (consumes the script directly from the tree) |
| upstream t2-ncm udev rules / NM handling | `nix/modules/t2-ncm` (NM_UNMANAGED rule; down-service retired upstream) |
| `packaging/installer/install-kernel-args.sh` (kernel args, modprobe blacklists, model conditionals) | `nix/modules/kait2en-kernel` `kernelParams`/blacklists + `amdgpuAspm`/`acpiOsiOverride` options with per-profile defaults in `nix/profiles/*` |
| macOS firmware extraction (installer) | `nix/pkgs/brcm-firmware` + `nix/modules/brcm-firmware` (local design, no 1:1 upstream file — review when the installer's firmware steps change) |
| `scripts/fedora/install-gpu-runtime-pm.sh` + `patches/runtime/gpu-runtime-pm/*` | **not ported yet** — candidate opt-in kernelPatches for dGPU profiles |

### Not consumed (changes never need porting)

`website/`, `data/`, `scripts/{ci,copr,macos,tests}`, `packaging/` (except
`install-kernel-args.sh` above), upstream `.github/**`,
`patches/{upstream,archived}/**` (opt-in candidates only), `PLAN.md`, docs.

### Local-only (ours; upstream never touches)

`flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `.agents/**`,
`apps/*/package.nix`, `apps/default.nix`, `modules/default.nix`,
`.github/workflows/nix.yml`, `nix/pkgs/kernel/patches/*`.

## Divergence register

| Patch | Drop condition |
|---|---|
| `patches/nixos/t2-fan-control-release-failsafe.patch` | upstream releases fans to SMC auto on daemon termination (SIGTERM handler or `--release`/ExecStopPost equivalent) |
| `patches/nixos/react-drm-touchbar-stateful-resume.patch` | upstream's `suspend.ts` gains an equivalent settle/wait on resume |
| `nix/pkgs/kernel/patches/0001-hid-add-spi-hid-device-types-and-macro.patch` (kernel ABI, not app) | `HID_SPI_DEVICE` + SPI `hid_type` members land in the in-tree `include/linux/hid.h` |

## Known blockers

- None currently. (Record held-back kernel bumps and unresolved upstream
  breakage here, with the blocking condition.)

## One-time setup state (done; verify if CI misbehaves)

- Repo secret `NIKS3_AUTH_TOKEN` must exist; the cache's public key is
  `garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss=` (set in both
  `.github/workflows/nix.yml` and the flake's `nixConfig`), and the niks3
  push invocation should be verified against the deployed version.
- Upstream's Fedora workflows are disabled in GitHub repo settings.
