# Upstream sync plan — catch up to `super/main` and Linux 7.2

Status snapshot (at time of writing):

- `HEAD` is **395 commits behind** `super/main`; merge-base is `dceca87`
  ("touchbar: select display configuration before BCE enumeration").
- Local-only commits fall into two groups:
  - **The Nix port** (keep): `a0a501e` add nixos support, `c5bf17a` port to
    Nix, `52fc83a` WIP kernel/ACP rule, `52fdddd` content-addressed hid patch,
    `b325e66`/`3131de9` initramfs module lists.
  - **Source-level hardware fixes** (mostly superseded upstream — audit, then
    prefer upstream): `412c5f1` touchbar stateful resume (upstream: `b9fb146`
    "restore stateful VHCI resume baseline" + EP0 stall recovery series),
    `4352e45`/`83b1cdf`/`02ac0b7` t2-fan-control tuning (upstream reworked
    fan-control heavily: v0.05, peak-hold, idle wakeups, advanced options),
    `430b883`/`262a883` t2-apple-audio-dsp tweaks (upstream replaced the whole
    DSP delivery mechanism).

## Phase 1 — Merge `super/main`

Do this **before** the kernel bump: upstream carries the 7.1 fix (`5d55656`,
multi-battery HID API) and the 7.2 fix (`6894352`) our modules need.

1. `git merge super/main`.
2. Conflict policy:
   - `modules/`, `apps/`, `scripts/`, `systemd/`, docs, `PLAN.md`, `README.md`:
     **take upstream** wholesale.
   - `flake.nix`, `nix/`, `modules/default.nix`, `apps/default.nix`,
     `apps/*/package.nix`: **keep ours** (fixed up in Phase 2).
3. Post-merge audit of each superseded local commit: diff our fix against the
   upstream equivalent; re-apply as a separate commit on top **only** if the
   behaviour is still missing (expected outcome: none survive).
4. Structural changes the merge brings (drives Phase 2):
   - `modules/t2bce` → `t2bce_core` (0.06) + `t2bce_dma` + `t2bce_vhci` +
     `t2bce_audio`. Cross-module build deps: core's dkms.conf passes
     `T2BCE_DMA_SRC=t2bce_dma`; vhci/audio link against core's exported
     symbols.
   - `modules/t2-apple-audio-dsp` → `t2bce_audio-dsp` (WirePlumber/PipeWire +
     udev, per `b45ca92`) and `t2bce_audio-alsa-ucm-conf` (ucm2 profiles,
     split speaker channels).
   - `modules/apfs` **deleted** upstream.
   - `modules/t2smp` **new** (SMP/CPU-offlining companion).
   - `modules/t2touchbar` no longer builds `t2touchbar_cfg` (only `t2hid`,
     `t2touchbar_bl`, `t2touchbar_kbd`). Verify where USB display-config
     selection moved (likely into the bce stack) before dropping it from our
     module lists.
   - `modules/t2thunderbolt`: removed then re-added upstream; its kernel arg
     was removed (`ca01a06`); no longer blacklists in-tree `thunderbolt`.
   - New top-level dirs we don't consume: `website/`, `packaging/`, `data/`,
     `.github/`. New `patches/` tree we *do* care about (see Phase 3).
   - New apps: `t2-cpu-control` (Python/GTK + polkit helper + resume unit),
     `t2-power-tune` (Python/GTK + polkit), `t2-dgpu-control`,
     `t2-hybrid-gpu-control`, `t2-power-explorer` (all three Rust/GTK with
     Cargo.lock).
   - Fedora kernel-arg set changed (`install-kernel-args.sh`): adds
     `i915.enable_guc=2`, `brcmfmac.p2pon=0`, `pcie_aspm=force`,
     `pcie_aspm.policy=powersave`, `pci=noaer`; `amdgpu.aspm=1` on
     MacBookPro15,1/15,3/16,1/16,4; **removes `acpi_osi` overrides on Titan
     Ridge and Ice Lake machines**; adds a modprobe.d "silent blacklist"
     (`install X /bin/true`).

## Phase 2 — Update the Nix layer

### `modules/default.nix` (kernel module packages)

- Replace `t2bce` with the four split packages. Packaging options, pick one:
  1. **One derivation `t2bce`** building core→dma→vhci→audio in order inside a
     single build (simplest; mirrors AUTOINSTALL ordering; no symvers
     plumbing), or
  2. Per-module derivations where `nix/kernel-module.nix` grows
     `extraSymbols`/`extraSrcDirs` support (`KBUILD_EXTRA_SYMBOLS` +
     `T2BCE_DMA_SRC`), letting each module rebuild independently.
  Start with (1); switch to (2) only if rebuild granularity matters.
- Add `t2smp`.
- Drop `apfs` (follow upstream). NixOS users can use nixpkgs'
  `linuxKernel.packages.*.apfs` instead — note this in the README/module docs.
- Sync versions from each module's `dkms.conf` (e.g. t2bce_core 0.06) instead
  of hardcoding, or at least bump them all.
- `t2touchbar`: outputs are now `t2hid`, `t2touchbar_bl`, `t2touchbar_kbd`.

### New non-kernel packages (`nix/pkgs/` or `modules/*/package.nix`)

- `t2bce_audio-alsa-ucm-conf`: install `ucm2/` into an alsa-ucm-conf overlay
  (extend `pkgs.alsa-ucm-conf` or set `ALSA_CONFIG_UCM2` via the NixOS
  module).
- `t2bce_audio-dsp`: filter graphs + WirePlumber config + udev rules; replaces
  our `nix/modules/t2-apple-audio-dsp` payload.

### `apps/`

- Refresh existing `package.nix` files against upstream changes:
  - `react-drm`: major (file-based routing, config-gui, icon themes, motion
    API, double-tap Fn). Re-vendor npm deps (`package-lock.json` changed),
    re-check `binding.gyp` native deps, new config blueprint files.
  - `t2-fan-control` (v0.05, gresource/UI changes), `t2-smc-control`
    (telemetry, battery bar, palette).
- Add packages for the five new apps:
  - Rust/GTK (`buildRustPackage` + wrapGAppsHook): `t2-dgpu-control`,
    `t2-hybrid-gpu-control`, `t2-power-explorer`.
  - Python/GTK (`python3.pkgs` + gobject-introspection): `t2-cpu-control`,
    `t2-power-tune`.
  - Each ships polkit `.policy` files and pkexec helper scripts → needs NixOS
    module wiring (below), not just a package.

### NixOS modules (`nix/modules/`)

- `kait2en-kernel`:
  - `loadModules`/`initrdModules`: replace `t2bce` with
    `t2bce_core t2bce_dma t2bce_vhci t2bce_audio`; drop `t2touchbar_cfg`
    (verify replacement mechanism first); add `t2smp`; keep the apfs note but
    point at nixpkgs.
  - `blacklistedModules`: drop `thunderbolt` (upstream no longer blacklists
    it).
  - `kernelParams`: add `i915.enable_guc=2`, `brcmfmac.p2pon=0`,
    `pcie_aspm=force`, `pcie_aspm.policy=powersave`, `pci=noaer`. Model
    conditionals become options + profile settings:
    - `hardware.kait2en.amdgpuAspm` (default per-profile for 15,1/15,3/16,1/16,4).
    - `hardware.kait2en.acpiOsiOverride` (default off for Titan Ridge / Ice
      Lake models, on otherwise — mirror the installer's PCI-ID probe as
      per-profile defaults since NixOS evals can't probe).
- Replace `t2-apple-audio-dsp` module with `t2bce-audio-dsp` +
  ucm2 wiring; update per-model DSP data (new 15,2 profile, 15,1 FIRs, 16,1
  defaults; 16,2 support was added then dropped — follow upstream).
- `kait2en-suspend`: re-sync `kait2en-suspend.sh` + unit with upstream.
- `t2-ncm`: pick up `be28092` (preserve NCM state across interface rename —
  udev *move* event) and current `kait2en-t2-ncm-down.sh`.
- New modules for new apps (polkit policies, helpers on PATH for pkexec,
  `t2-cpu-control` resume service, persistent CPU settings `579b072`,
  persistent SMC charge limit `5f9d1b7`).
- Consider a `gpu-runtime-pm` option applying
  `patches/runtime/gpu-runtime-pm/*` as kernelPatches for dGPU models
  (upstream installs these at runtime on Fedora; on NixOS they belong in the
  kernel build).
- Evaluate `acpi-autofix` (`d825558`): if it produces a patched DSDT, port as
  `boot.initrd` ACPI table override; otherwise skip (Fedora-installer-only).
- `nix/profiles/`: update the three existing profiles for the new options;
  consider adding `macbookpro15-1`/`15-2` now that upstream supports them
  (DSP + hybrid GPU + aspm work all target them).

## Phase 3 — Kernel bump to 7.2 (nixpkgs-unstable)

Do this **last** — the merged module sources are what build against 7.2.

1. `nix flake update nixpkgs` (lock is from 2026-06-16; unstable now ships
   `linux_7_2`).
2. `nix/pkgs/kernel/default.nix`: take `linux_7_2` instead of `linux_7_0`
   (update the three call sites in `flake.nix` and
   `nix/modules/kait2en-kernel`). Consider renaming the parameter to a
   neutral `linuxKernel` so future bumps touch one file.
3. The SPI-HID ABI patch
   (`0001-hid-add-spi-hid-device-types-and-macro.patch`):
   - Upstream `hid_t2magicmouse` **still references `HID_SPI_DEVICE`**, so the
     patch is still required *unless* 7.2 gained the enum/macro in-tree —
     check `include/linux/hid.h` in 7.2 first; drop the patch if upstream now
     has it, otherwise rebase it onto 7.2 (also re-check `t2hid`).
4. Optionally adopt upstream's kernel patch tree as opt-in kernelPatches:
   - `patches/upstream/submitted/apple-t2-early-cpu-offlining-v1` (pairs with
     `t2smp`),
   - `patches/upstream/prepared/apple-t2-thunderbolt-device-links-v8`,
   - `patches/upstream/submitted/fn-double-press-v3`,
   - `patches/runtime/gpu-runtime-pm/*` (dGPU profiles only).
   Skip `patches/archived/**` (already merged upstream or withdrawn).
5. Rebuild everything; fix any 7.2 fallout not covered by upstream's
   `6894352`.

## Phase 4 — Validation

- `nix flake check` + `nix fmt`.
- Build matrix: `nix build .#kernel`, every module package (against the
  7.2 kait2enKernel), every app.
- Eval test: minimal NixOS config importing each `nixosModule` and each
  profile (catches option renames, e.g. removed `t2touchbar_cfg`,
  `forceIgd`-style removals for the dropped audio module).
- On-hardware smoke test (MacBookPro16,1): boot, Touch Bar (react-drm),
  internal keyboard/trackpad, speakers + headphone jack (new bce_audio path —
  upstream fixed headphone crackling in `46a7b12`), Wi-Fi/BT, suspend/resume
  **twice** (the historical failure mode), fan + SMC apps, charge-limit
  persistence.

## Ordering / commit strategy

1. Merge commit (`super/main`), conflicts resolved per Phase 1.
2. One commit per Phase 2 bullet (module split packaging, audio-dsp swap,
   each new app + its NixOS module, kernel-arg sync, suspend/ncm sync,
   profiles).
3. Kernel bump commit(s): flake.lock update, then linux_7_2 switch + patch
   rebase.
4. Follow-up commit removing this file once executed, folding durable notes
   into `README.md`/module docs.

## Known risks

- **bce split cross-module builds in Nix** — symvers/`T2BCE_DMA_SRC` plumbing
  is the trickiest packaging change; the single-derivation fallback bounds it.
- **react-drm node build** — big diff, node-gyp; expect npm-deps hash churn
  and possible new native libs.
- **`t2touchbar_cfg` removal** — must confirm the display-config selection
  replacement before dropping it from initrd, or the Touch Bar regresses to
  black at boot.
- **`acpi_osi` conditional** — removing overrides is per-Thunderbolt-gen; a
  wrong default breaks hotplug on older machines. Encode as explicit profile
  defaults, never a global.
- **7.2 HID patch drift** — if the hunk no longer applies, the failure mode is
  a full kernel build error (cheap to catch), but check whether 7.2 obsoletes
  the patch entirely first.
