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
| `modules/**`, `apps/**`, `t2-services/**`, `dsp/**` *sources* (not the nix files below), `scripts/`, `assets/`, `auto-installer/`, `packaging/`, `third-party/`, `website/`, upstream `.github/**` except `workflows/`, `patches/**` except `patches/nixos`, docs/licences | **theirs**, unconditionally |
| `flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `.agents/**`, `apps/*/package.nix`, `t2-services/*/package.nix`, `dsp/package.nix`, `apps/default.nix`, `modules/default.nix`, `Justfile`, `treefmt.nix`, `default.nix`, `shell.nix`, `.envrc`, `.zed/**`, `.forgejo/**`, `.github/workflows/lint.yaml` | **ours** (reconciled via the mirror map, not the merge) |
| upstream's `.github/workflows/*.yml` (`installer`, `pages`, `kernel-copr`, `blog-discord`, `upstream-discord`) | **deleted deliberately** — Fedora-specific, and this fork's CI is Forgejo. A modify/delete conflict here resolves as *ours*: `git rm` it and move on. Do **not** restore them. |
| anything else | read both sides, decide, and add a mirror-map row so next time it's covered |

When upstream renames/deletes a directory that holds one of our
`package.nix` files, git reports a "file location" conflict and suggests a
new location: accept it in the merge commit (`git add` the suggested path),
then move/delete it properly in the reconciliation commits.

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
  `nix/modules/t2-force-click` / `nix/modules/t2-services` for the canonical
  shape). Units the installer writes *inline* (heredocs in
  `scripts/fedora/install-*.sh`) count as upstream units too.
- **Runtime paths**: grep every new or changed app for absolute paths
  (`/run/`, `/var/`, `/etc/`, `/usr/local/`, `/usr/share/`) — *and its
  `.desktop` `Exec=` line*. Each must resolve on NixOS: `RuntimeDirectory`
  for `/run/<name>`, `StateDirectory` + a `substituteInPlace` to
  `/var/lib/<name>` for persistent state the daemon writes,
  store-path substitution for data files (the wordmark goes through
  `nix/lib/kait2en-polkit.nix` `rewriteFhsPaths`; fonts through
  `nix/pkgs/kait2en-branding`). `Command::new("<tool>")` calls need the tool on
  the wrapper's or unit's PATH.
- **Kernel args**: `scripts/fedora/install-kernel-args.sh` is the source
  of truth for upstream's kernel parameters and modprobe blacklists;
  `scripts/fedora/rebuild-initramfs.sh` `EARLY_MODULES` for the initrd list.
  DMI/PCI-conditional args map to options (`hardware.kait2en.amdgpuAspm`,
  `pcieAspm`, `acpiOsiOverride`) whose defaults follow the installer's
  *generic* branch and which every profile sets explicitly — the installer
  probes DMI/PCI that Nix eval cannot.
- **App → model mapping** (`install-apps.sh` `install_gpu_control`, Touch Bar
  presence, …) maps to profile settings; re-read it every sync.

### 5. Audit the divergence register

For each patch in `patches/nixos/` (register below): is its **drop condition**
met? Drop it. Does it still apply (`patch -p1 --dry-run` in the app dir)?
If not, upstream touched the same code — re-evaluate whether the divergence is
still needed before rebasing it. Update the register. The ideal count is zero.

### 6. Kernel

Policy: the base kernel **matches the series Fedora stable ships** (what
upstream targets). Query it:

```sh
curl -s 'https://bodhi.fedoraproject.org/updates/?packages=kernel&status=stable&rows_per_page=10' \
  | jq -r '.updates[] | select(.release.name != "ELN") | select(.title | test("rc") | not) | .title' | head -3
```

(Rawhide/ELN rc kernels are listed first; skip them.) Re-check the SPI-HID
patch without building: realise only the kernel `src` (a download), extract
`include/linux/hid.h` and `patch -p1 --dry-run`.

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
   before merging: boot; Touch Bar (`kait2en-touchbar`); internal keyboard +
   trackpad + Force Click; Touch ID (`fprintd-enroll`/`fprintd-verify`);
   speakers, headphone jack and both mics (UCM + DSP; on a machine coming
   from the ACP integration, reset the T2 entries in
   `~/.local/state/wireplumber/default-{profile,nodes,routes}` first);
   Wi-Fi/BT; **suspend/resume twice** (the historical failure mode); fan,
   SMC, zone-power and GPU apps (hybrid: `modinfo -n amdgpu` is the
   `updates/kait2en-gpu-runtime-pm` module, vga_switcheroo shows
   DynOff/DynPwr); AVE (`t2remote`); charge limit via t2sbs
   (`charge_control_end_threshold`) and RTC (`hwclock`) persistence across
   reboot. Add items for whatever this sync touched.

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
| `modules/t2bce_core`, `t2bce_dma`, `t2bce_vhci`, `t2bce_audio`, `t2bce_stack`, `t2-services/t2-ave/kernel/t2bce_ave` | single `t2bce` derivation (dma→core→vhci→audio→ave build order via upstream's `t2bce_stack`; `t2bce_ave` staged as a sibling like `install-dkms-modules.sh` `copy_module_source`, loaded only by `services.t2-ave`) |
| `modules/t2smc` | `t2smc` (initrd) |
| `modules/t2sbs` | `t2sbs` (initrd; Smart Battery `charge_control_end_threshold`, replaces the blacklisted in-tree `sbs`) |
| `modules/t2bdrm` | `t2bdrm` |
| `modules/t2gmux` | `t2gmux` |
| `modules/t2smp` | `t2smp` |
| `modules/t2mfi_fastcharge` | `t2mfi_fastcharge` |
| `modules/hid_t2magicmouse` | `hid_t2magicmouse` (needs the SPI-HID ABI kernel patch; external mice only now) |
| `modules/t2_precision_trackpad`, `modules/t2_trackpad_actuator` | `t2_precision_trackpad`, `t2_trackpad_actuator` (internal trackpad + Force Click haptics) |
| `modules/t2touchbar` | `t2touchbar` (`t2hid` (initrd), `t2touchbar_bl`, `t2touchbar_kbd`) |
| `modules/t2thunderbolt` | `t2thunderbolt` |
| `scripts/fedora/install-dkms-modules.sh`, `rebuild-initramfs.sh` `EARLY_MODULES` | `loadModules` / `initrdModules` defaults |
| `modules/apfs` | **dropped, following upstream** — point users at nixpkgs' apfs |
| `modules/t2sep` | **not packaged** — upstream legacy (Touch ID moved to `t2-services/t2-touchid`) |

Version bumps in any `dkms.conf` must land in the matching derivation.

### GPU

| Upstream sources | Ours |
|---|---|
| `scripts/fedora/install-gpu-runtime-pm.sh` + `patches/runtime/gpu-runtime-pm/{series,*.patch}` | `nix/pkgs/gpu-runtime-pm` (out-of-tree amdgpu from `kernel.src` + the series against `kernel.dev`, installed to `updates/kait2en-gpu-runtime-pm`; mirrors the script's `patch_needed_for_kernel` skip list, `--forward --fuzz=3` + already-applied tolerance and the `TRACE_INCLUDE_PATH` sed) + `hardware.kait2en.gpuRuntimePm` (`softdep amdgpu pre: t2gmux`). Upstream's supported-model list → profiles enable it (15,1 / 16,1 / 16,4; iMac20,x if a profile is added). New entries in `patch_needed_for_kernel` → `patchNeeded`. |
| `apps/t2-dgpu-control`, `apps/t2-hybrid-gpu-control` (+ `install-apps.sh` `install_gpu_control` model map) | `package.nix` each + shared `nix/modules/t2-gpu-control` (`gpuControl.mode = "dgpu" | "hybrid"`; hybrid warns without `gpuRuntimePm`) |

### Audio

| Upstream sources | Ours |
|---|---|
| `dsp/` (`profiles/`, `config/models.json`, `tools/build.py`, `integration/wireplumber`, `Makefile` `install`) | `dsp/package.nix` (`t2-dsp`: build.py + the Makefile's install layout into `$out`) |
| `scripts/fedora/install-dsp.sh`, `packaging/lifecycle` `configure_dsp_pipewire` | `nix/modules/t2bce-audio-dsp`: udev + WirePlumber from the package, the `model`'s `share/t2-dsp/pipewire/<model>.conf` as `pipewire.conf.d/51-t2-dsp.conf` (replaces the lifecycle's DMI pick), LV2 via `requiredLv2Packages` |
| `modules/t2bce_audio-alsa-ucm-conf/ucm2`, `scripts/fedora/install-alsa-ucm.sh` | `nix/pkgs/t2bce_audio-alsa-ucm-conf` (stock tree + AppleT2 overlay) → `ALSA_CONFIG_UCM2` on pipewire/wireplumber + `environment.variables` |

New `dsp/profiles/<model>` / `models.json` entries → extend the module's
`model` enum + consider a new profile.

### Apps → `apps/<name>/package.nix` + NixOS module

| Upstream sources (incl. their `.service`/`.policy`/udev/helpers) | Ours |
|---|---|
| `apps/t2-touchbar` (`integration/{udev,systemd}`, `config/`, `install.sh`) | `package.nix` (`kait2en-touchbar`) + `nix/modules/t2-touchbar` |
| `apps/t2-fan-control` | `package.nix` + `nix/modules/t2-fan-control` + divergence patch (register) |
| `apps/t2-smc-control` (`systemd/t2-smc-gaugingd.service`) | `package.nix` + `nix/modules/t2-smc-control` (gauging daemon; `StateDirectory`) |
| `apps/t2-zone-power` (`systemd/t2-zonepowerd.service`) | `package.nix` + `nix/modules/t2-zone-power` |
| `apps/t2-force-click` (`systemd/t2-force-click.service`) | `package.nix` + `nix/modules/t2-force-click` |
| `apps/t2-power-tune` | `package.nix` + `nix/modules/t2-power-tune` |
| `apps/t2-power-explorer` | `package.nix` + `nix/modules/t2-power-explorer` |
| `apps/t2-kernel-builder` | **not ported** — Fedora COPR tooling; our kernel comes from nixpkgs |
| `assets/kait2en-app-logo.png`, `assets/fonts` (`install-apps.sh` `install_app_assets`) | `nix/pkgs/kait2en-branding` (wordmark + JetBrains Mono → `fonts.packages`) + `nix/lib/kait2en-polkit.nix` `rewriteFhsPaths` |

### t2-services → `t2-services/<name>/package.nix` + `nix/modules/t2-services`

| Upstream sources | Ours |
|---|---|
| `t2-services/shared/{protocols,Makefile}` | `nix/lib/t2-services-src.nix` (crate + `shared/` source filter) |
| `t2-services/shared/integration/{NetworkManager,systemd,libexec/t2-ncm-sleep}`, `scripts/fedora/install-t2-services-common.sh` | `services.t2-services` (NM `no-auto-default` + "Apple T2 Bridge" profile, `t2-services-suspend` + sleep.d hook linkFarm) |
| `t2-services/t2-ave` (`integration/systemd`, sleep hook), `scripts/fedora/install-t2-remote.sh` | `package.nix` + `services.t2-ave` |
| `t2-services/t2-touchid` (`integration/{systemd,fprintd,dbus}`, `config/`), `scripts/fedora/install-touchid.sh` | `package.nix` + `services.t2-touchid` (fprintd from `services.fprintd`; SELinux policy not consumed) |
| `t2-services/t2-journal` | `package.nix` only (CLI) |

### System integration

| Upstream sources | Ours |
|---|---|
| `scripts/fedora/install-suspend-service.sh` (inline unit) + `scripts/fedora/kait2en-suspend.sh` | `nix/modules/kait2en-suspend` (consumes the script directly from the tree) |
| `scripts/fedora/install-rtc-sync.sh` (inline unit) | `nix/modules/kait2en-rtc-sync` |
| `scripts/fedora/install-kernel-args.sh` (kernel args, modprobe blacklists, model conditionals) | `nix/modules/kait2en-kernel` `kernelParams`/blacklists + `amdgpuAspm`/`pcieAspm`/`acpiOsiOverride`, set per profile in `nix/profiles/*` |
| macOS firmware extraction (`auto-installer/runtime/install-{wifi,bt}-firmware.sh`) | `nix/pkgs/brcm-firmware` + `nix/modules/brcm-firmware` (local design, no 1:1 upstream file — review when the firmware steps change) |

### Not consumed (changes never need porting)

`website/`, `data/`, `scripts/{ci,copr,macos,tests}`, `auto-installer/`,
`packaging/` (incl. `packaging/lifecycle`, apart from the
`configure_dsp_pipewire` semantics above), `apps/deprecated/`,
`modules/t2sep`, `third-party/` (only hex2hcd; unused),
`assets/{plymouth,gdm}` and the other logos, `scripts/fedora/{acpi-autofix.py,
install-acpi-fixes.sh}` (runtime ACPI table extraction — candidate for a
future port), `scripts/fedora/{install-hardware-video-decoding.sh,
install-gdm-branding.sh, install-plymouth-theme.sh, install-dependencies.sh,
build-installer.sh, kait2en-multicall, lib.sh, install.sh, other/,
deprecated/}`, `t2-services/*/packaging`,
`t2-services/shared/integration/{migration,libexec/package-actions}`,
`dsp/{tests,packaging,integration/libexec}`,
`patches/{upstream,archived,currently-testing}/**` (opt-in candidates only),
upstream `.github/**`, `PLAN.md`, docs, `LICENSE*`/`LICENSING.md`/`AUTHORS`/
`TRADEMARK.md`/`VALUES.md`.

### Local-only (ours; upstream never touches)

`flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `.agents/**`,
`apps/*/package.nix`, `apps/default.nix`, `t2-services/*/package.nix`,
`dsp/package.nix`, `modules/default.nix`, `default.nix`, `shell.nix`,
`treefmt.nix`, `Justfile`, `.envrc`, `.zed/**`, `.forgejo/**`,
`.github/workflows/lint.yaml`, `nix/pkgs/kernel/patches/*`.

## Divergence register

| Patch | Drop condition |
|---|---|
| `patches/nixos/t2-fan-control-release-failsafe.patch` (rebased onto upstream's reworked `control.rs` in the 2026-10-17 sync; rebased again in the 2026-10-19 sync for the native-SMC switch — upstream now releases at *startup* in native mode, not on termination). Its `--release` relies on t2smc treating `fanN_target=0` as hand-back (upstream `513a82d`); with older t2smc that write latched the fan in manual mode at 0 rpm | upstream releases fans to SMC auto on daemon termination (SIGTERM handler or `--release`/ExecStopPost equivalent) |
| `patches/nixos/t2-power-tune-vhci-exclude.patch` (added in the 2026-10-19 sync; was the in-tree edit `92d2a1b`) | upstream's `t2-power-tune-helper` excludes `t2bce_vhci` devices from the wakeup/runtime-PM tunables in `scan()` and `validate()` |
| `nix/pkgs/kernel/patches/0001-hid-add-spi-hid-device-types-and-macro.patch` (kernel ABI, not app) | `HID_SPI_DEVICE` + SPI `hid_type` members land in the in-tree `include/linux/hid.h` |

(`patches/runtime/gpu-runtime-pm` is upstream's own series, consumed via the
GPU row, not a divergence.)

## Known blockers

- **Gate not run locally (2026-10-17 and 2026-10-19 syncs)**: the dev machine
  cannot take heavy builds; only eval (`drvPath`s of every package + the three
  `check-*` toplevels) was verified. CI's `nix flake check` is the gate —
  in particular the new out-of-tree amdgpu (`gpu-runtime-pm`) and `t2-dsp`
  have never been built.
- **Keyboard backlight LED rename** (`apple::kbd_backlight` →
  `:white:kbd_backlight`): the saved brightness is lost once after upgrading.

## One-time setup state (done; verify if CI misbehaves)

- Forge repo secret `NIKS3_CI_TOKEN` must exist; the cache's public key is
  `garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss=` (set in the flake's
  `nixConfig`; CI gets it from nixham's `setup-nix-shell`/`niks3-push`
  actions).
- Upstream's Fedora workflows are **deleted**, not disabled: `origin` is now
  the forge (`forge.channings.me/hartlandia/KaiT2en-NixOS`) and GitHub is the
  mirror. Forgejo ignores `.github/workflows` whenever `.forgejo/workflows`
  exists, so only `.forgejo/` runs on the forge.
- `scripts/tests/static-check.sh` (upstream's) asserts on
  `.github/workflows/installer.yml`, which no longer exists here, so that
  script fails on this fork. Nothing in our CI runs it — the gate is
  `just test` — but do not treat its failure as a regression.
