---
name: sync-upstream
description: Reconcile a staged upstream sync into the Nix layer. Runs on the bot-created `sync/upstream` branch, comparing against `main`: packages apps upstream added, finds and fixes breaking changes, represents new systemd services as NixOS modules, audits divergence patches, bumps the kernel, and takes the build gate green. Invoke by path from the repo root.
---

# Reconcile the staged upstream sync

A scheduled Forgejo job (`.forgejo/workflows/upstream-sync.yaml`, nixham's
`upstream-sync` action) merges `kaiT2en/KaiT2en-Fedora` into a **`sync/upstream`**
branch every Monday and opens a PR against `main`. **The merge is already done
when this skill runs.** Your job is everything the bot cannot do: reconcile the
merged upstream sources into the Nix layer and take the gate green.

**Run this skill on `sync/upstream`, comparing against `main`.**

**Philosophy:** `modules/`, `apps/`, `t2-services/` and `dsp/` *sources* stay
**byte-identical to upstream**. Everything NixOS-specific lives in the Nix layer
(`nix/`, `*/package.nix`, `*/default.nix`, `patches/nixos/`). Divergence policy:
**upstream it > drop it > patch it** — a patch is a last resort and must carry a
drop condition (recorded in its header), re-checked every run.

**Done** = every pass below closed out, green `nix flake check`, commits pushed
to `sync/upstream`, PR body updated. Do not merge it yourself — the hardware
gate is the user's.

## Procedure

### 1. Orient

```sh
git checkout sync/upstream && git pull
MERGE=$(git rev-list --merges --max-count=1 HEAD)   # the bot's merge commit
PREV=$(git rev-parse "$MERGE^1")                    # our main as the bot found it
NEW=$(git rev-parse "$MERGE^2")                     # upstream tip merged in
LAST_SYNC=$(git merge-base "$PREV" "$NEW")          # previous catch-up point
```

`$LAST_SYNC..$NEW` is the upstream delta this run must reconcile; `main...HEAD`
is everything the PR currently contains. Read both before touching anything:

```sh
git log --oneline $LAST_SYNC..$NEW
git diff --stat $LAST_SYNC $NEW
```

Sanity-check the bot's merge — it resolves by path ownership, and a bad
resolution poisons every pass that follows:

| Paths | Expected resolution |
|---|---|
| `modules/**`, `apps/**`, `t2-services/**`, `dsp/**` *sources*, `scripts/`, `assets/`, `auto-installer/`, `packaging/`, `third-party/`, `website/`, `patches/**` except `patches/nixos`, docs/licences | **theirs** |
| `flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `skills/**`, `apps/*/package.nix`, `t2-services/*/package.nix`, `dsp/package.nix`, `apps/default.nix`, `modules/default.nix`, `Justfile`, `treefmt.nix`, `default.nix`, `shell.nix`, `.envrc`, `.zed/**`, `.forgejo/**`, `.github/workflows/lint.yaml` | **ours** (reconciled by you, not by the merge) |
| upstream's `.github/workflows/*.yml` (`installer`, `pages`, `kernel-copr`, `blog-discord`, `upstream-discord`) | **absent** — Fedora-specific, deleted deliberately; this fork's CI is Forgejo. Do not restore them. |

Verify with `git show --stat $MERGE -- nix/ flake.nix apps/default.nix
modules/default.nix patches/nixos/` (expect empty) and
`git show --stat $MERGE -- .github/` (expect empty). If the merge went wrong,
fix it as a commit on top rather than re-merging — the PR is already open.

If the delta contains a structural upheaval you cannot resolve confidently in
one pass (a directory split, a build-system rewrite), reconcile the rest, land
it green, and take the upheaval as its own follow-up commit series.

### 2. Pass A — apps that aren't packaged or integrated

Upstream adds apps freely; each needs a `package.nix`, registration, and —
if it ships any unit, policy, udev rule or helper — a NixOS module.

```sh
for d in apps/*/ t2-services/*/; do
  case "$d" in apps/deprecated/*|t2-services/shared/) continue ;; esac
  [ -f "$d/package.nix" ] && continue
  echo "unpackaged: $d"
done
```

Then catch the packaged-but-unwired case — a `package.nix` that exists but is
not registered, or a package with no module despite shipping integration:

```sh
for d in apps/*/package.nix; do
  n=$(basename "$(dirname "$d")")
  grep -q "$n" apps/default.nix || echo "unregistered: $n"
done
ls apps/*/systemd apps/*/integration/systemd t2-services/*/integration/systemd 2>/dev/null
```

For each hit, decide **port** or **explicitly decline**, and record the decision
as a mirror-map row (declines go in the row with a reason, e.g.
`t2-kernel-builder` → *not ported — Fedora COPR tooling*). Never leave an app
unclassified.

To port one:

- Write `apps/<name>/package.nix` following sibling conventions:
  `lib.cleanSource ./.`; `buildRustPackage` + `wrapGAppsHook4` for Rust/GTK,
  `python3Packages` + `gobject-introspection` for Python/GTK, `buildNpmPackage`
  for node. Match the upstream `Makefile`'s `install` layout into `$out`.
- Register it in `apps/default.nix` (or `t2-services/*` in the t2-services set).
- Give it `nix/modules/<name>/` if it ships a `.service`, `.policy`, udev rule,
  D-Bus service or pkexec helper, and enable it in the relevant
  `nix/profiles/*`.
- Grep it for absolute paths (`/run/`, `/var/`, `/etc/`, `/usr/local/`,
  `/usr/share/`) — *and its `.desktop` `Exec=` line*. Each must resolve on
  NixOS: `RuntimeDirectory` for `/run/<name>`, `StateDirectory` +
  `substituteInPlace` to `/var/lib/<name>` for persistent state, store-path
  substitution for data files (wordmark via `nix/lib/kait2en-polkit.nix`
  `rewriteFhsPaths`, fonts via `nix/pkgs/kait2en-branding`).
  `Command::new("<tool>")` calls need the tool on the wrapper's or unit's PATH.
- New kernel module dir (`modules/<name>/` with a `dkms.conf`): package it in
  `modules/default.nix` (see `mkSimple` / `buildKernelModule`), sync the version
  from `dkms.conf`, and wire it into `nix/modules/kait2en-kernel`'s
  `loadModules` / `initrdModules` as upstream's installer does.

### 3. Pass B — breaking changes

Upstream changes that silently invalidate the Nix layer. Start from what moved:

```sh
git diff --diff-filter=RD --name-status -M $LAST_SYNC $NEW   # deletions + renames
```

Every deleted or renamed path is a breaking-change candidate: grep the Nix layer
for its basename, and for each hit decide whether to follow the rename, drop the
reference, or keep a local copy.

```sh
git diff --diff-filter=RD --name-only -M $LAST_SYNC $NEW \
  | while read -r p; do
      git grep -l "$(basename "$p")" -- 'nix/**' '*/package.nix' '*/default.nix' \
        | sed "s|^|BREAKS (${p}): |"
    done
```

Then sweep the categories that break without deleting a file:

- **`dkms.conf` version or module-name bumps** —
  `git diff $LAST_SYNC $NEW -- 'modules/**/dkms.conf'`; each must land in the
  matching `modules/default.nix` derivation and in `loadModules`/`initrdModules`.
- **Build-system changes** — `Makefile` `install` layout, `Cargo.toml`
  dependency and binary-name changes, new `build.rs` codegen, new
  `build-dependencies` needing a `nativeBuildInput`. A renamed binary breaks
  every unit `ExecStart` and `.desktop` `Exec=` that names it.
- **Helper, CLI-flag and D-Bus-name changes** — our modules hardcode these in
  native unit definitions; a renamed flag fails only at runtime.
- **State and runtime path changes** — a daemon that starts writing somewhere
  new needs the matching `StateDirectory`/`RuntimeDirectory` and
  `substituteInPlace`.
- **Kernel args and blacklists** — `scripts/fedora/install-kernel-args.sh` is
  the source of truth for upstream's kernel parameters and modprobe blacklists;
  `scripts/fedora/rebuild-initramfs.sh` `EARLY_MODULES` for the initrd list.
  DMI/PCI-conditional args map to options (`hardware.kait2en.amdgpuAspm`,
  `pcieAspm`, `acpiOsiOverride`) whose defaults follow the installer's *generic*
  branch and which every profile sets explicitly — the installer probes DMI/PCI
  that Nix eval cannot.
- **App → model mapping** — `install-apps.sh` `install_gpu_control`, Touch Bar
  presence, new `dsp/profiles/<model>` and `config/models.json` entries map to
  profile settings and to the `t2bce-audio-dsp` `model` enum. Re-read every sync.

Fix each as you find it; the gate in step 7 only catches the subset that breaks
evaluation or the build.

### 4. Pass C — systemd services not represented in the NixOS modules

Upstream ships `.service` files that hardcode `/usr/local/...` and cannot be
consumed directly. We re-declare each as a **native `systemd.services.*`
definition** in the app's NixOS module, with a header comment naming the
upstream unit it mirrors. See `nix/modules/t2-force-click` and
`nix/modules/t2-services` for the canonical shape.

Find units with no counterpart:

```sh
for f in $(find apps t2-services dsp \
    \( -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.path' \) \
    -not -path '*/deprecated/*' | sort); do
  u=$(basename "$f"); u=${u%.*}
  grep -rqF "$u" nix/modules/ || echo "UNCOVERED: $f"
done
```

Also catch the ones that are covered but drifted, and the units that never
appear as files at all:

```sh
git diff $LAST_SYNC $NEW -- '*.service' '*.timer' '*.socket' '*.path' \
  '*/integration/systemd/*' '*/systemd/*'
git diff $LAST_SYNC $NEW -- 'scripts/fedora/install-*.sh' | grep -iE 'cat >|<<.?EOF|\.service'
```

Units the installer writes **inline** (heredocs in `scripts/fedora/install-*.sh`)
count as upstream units too — `kait2en-suspend` and `kait2en-rtc-sync` both come
from there.

For every new, changed or uncovered unit — **and the helpers its `Exec` lines
run** — reconcile semantically against our module. Judge semantics, not bytes: a
`/usr/local` path shuffle usually needs nothing; a new `ExecStartPre`,
`After=`/`Wants=` edge, `Environment=`, hardening directive, state path, or a
changed `Exec` helper always does. User units (`integration/systemd/user/`) map
to `systemd.user.services.*`. Sleep hooks map to the `systemd.sleep` /
`linkFarm` pattern in `services.t2-services`. Record declines ("D-Bus activation
only, no unit needed") in the mirror map.

### 5. Sweep — mirror-map reconciliation

Passes A–C cover apps, breakage and units. This pass catches everything else and
proves nothing was missed.

For **every row** in the mirror map (below), run
`git diff $LAST_SYNC $NEW -- <upstream sources>`. Non-empty diff → a mandatory
checklist item: read the upstream diff *and* our counterpart, then either apply
the semantic change to the Nix layer or record "no action — cosmetic" in the PR
body.

Then diff the **whole tree**: any path changed in `$LAST_SYNC..$NEW` that is not
covered by a map row, the not-consumed list, or a decision from passes A–C is an
**unmapped upstream change** — classify it (new row, or an explicit not-consumed
entry) before proceeding. Never leave a path unclassified.

### 6. Audit the divergence register

For each patch in `patches/nixos/` (register below): is its **drop condition**
met? Drop it. Does it still apply (`patch -p1 --dry-run` in the app dir)? If
not, upstream touched the same code — re-evaluate whether the divergence is
still needed before rebasing it. Update the register. The ideal count is zero.

### 7. Kernel

Policy: the base kernel **matches the series Fedora stable ships** (what
upstream targets). Query it:

```sh
curl -s 'https://bodhi.fedoraproject.org/updates/?packages=kernel&status=stable&rows_per_page=10' \
  | jq -r '.updates[] | select(.release.name != "ELN") | select(.title | test("rc") | not) | .title' | head -3
```

(Rawhide/ELN rc kernels are listed first; skip them.) Re-check the SPI-HID patch
without building: realise only the kernel `src` (a download), extract
`include/linux/hid.h` and `patch -p1 --dry-run`.

If Fedora moved to a new series and the merged module sources support it
(upstream lands compat commits before Fedora ships): `nix flake update nixpkgs`,
bump the single `baseKernel` line in `nix/pkgs/kernel/default.nix`, and
**re-check the SPI-HID ABI patch** against the new kernel's
`include/linux/hid.h` (drop it if `HID_SPI_DEVICE` went in-tree; rebase if the
hunk drifted). If the gate then fails on the new kernel, hold the kernel back
one series (keep the nixpkgs bump) and record the blocker under Known blockers.
Kernel changes are their own commit.

### 8. Gate

```sh
nix fmt
nix flake check -L     # or: just test
```

The checks output is the complete gate: every package (kernel included) and the
three per-profile NixOS toplevels. Fix forward until green. Checks derive from
the package set and `checkConfigurations` in `flake.nix` — new packages and
profiles are gated automatically, but a new *profile* must be added to
`checkConfigurations`. Every app packaged in pass A is gated the moment it is
registered, which is the point of registering it.

### 9. Land

Commit **on top of the bot's merge** — never rewrite or re-create it. One commit
per reconciled area: app packaging (one per app + its module), breaking-change
fixes, service reconciliations, kernel-arg sync, kernel bump. Updates to this
file (mirror map, divergence register, known blockers) belong in the same
series.

```sh
git push origin sync/upstream
```

The PR is already open — update its body (`gh pr edit`, or the forge UI) to
contain:

1. The delta (`$LAST_SYNC..$NEW` summary) and per-row reconciliation outcomes,
   including the "no action — cosmetic" entries.
2. Pass A/B/C results: apps packaged or declined (with reasons), breaking
   changes found and how they were fixed, services newly represented or
   declined.
3. Divergence register changes (dropped/rebased/added patches).
4. The kernel decision and why.
5. The **hardware smoke checklist** — the merger runs it on a T2 machine before
   merging: boot; Touch Bar (`kait2en-touchbar`); internal keyboard + trackpad +
   Force Click; Touch ID (`fprintd-enroll`/`fprintd-verify`); speakers,
   headphone jack and both mics (UCM + DSP; on a machine coming from the ACP
   integration, reset the T2 entries in
   `~/.local/state/wireplumber/default-{profile,nodes,routes}` first); Wi-Fi/BT;
   **suspend/resume twice** (the historical failure mode); fan, SMC, zone-power
   and GPU apps (hybrid: `modinfo -n amdgpu` is the
   `updates/kait2en-gpu-runtime-pm` module, vga_switcheroo shows
   DynOff/DynPwr); AVE (`t2remote`); charge limit via t2sbs
   (`charge_control_end_threshold`) and RTC (`hwclock`) persistence across
   reboot. **Add items for whatever this sync touched** — every app packaged in
   pass A needs a line.

CI builds the PR and pushes to `nix.channings.me`, so the smoke-test machine
substitutes instead of building.

## Mirror map

Every upstream artifact we consume and its NixOS counterpart. Reconcile each row
in step 5; keep this table current — an upstream change with no row and no
not-consumed entry is a policy violation.

### Kernel modules → `modules/default.nix` attrs + `nix/modules/kait2en-kernel` lists

| Upstream sources | Ours |
|---|---|
| `modules/t2bce_core`, `t2bce_dma`, `t2bce_vhci`, `t2bce_audio`, `t2bce_stack`, `t2-services/t2-ave/kernel/{t2bce_ave,t2bce_sidecar}` | single `t2bce` derivation (dma→core→vhci→audio→ave→sidecar build order via upstream's `t2bce_stack`; `t2bce_ave` and `t2bce_sidecar` staged as siblings like `install-dkms-modules.sh` `copy_module_source`; `t2bce_ave` loaded only by `services.t2-ave`, `t2bce_sidecar` autoloads by modalias) |
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
| `apps/t2-dgpu-control`, `apps/t2-hybrid-gpu-control` (+ `install-apps.sh` `install_gpu_control` model map) | `package.nix` each + shared `nix/modules/t2-gpu-control` (`gpuControl.mode = "dgpu" \| "hybrid"`; hybrid warns without `gpuRuntimePm`) |

### Wireless

| Upstream sources | Ours |
|---|---|
| `scripts/fedora/install-wireless.sh` + `patches/runtime/wireless/{series,*.patch}` | `nix/pkgs/wireless` (brcmfmac + wcc/cyw/bca, hci_uart, hci_bcm4377, btbcm from `kernel.src` + the series against `kernel.dev`, installed to `updates/kait2en-wireless`; mirrors `select_modules` against the kernel's `.config`, the `BT_BCM` handling and `apply_patch_if_needed`) + `hardware.kait2en.wireless`, on in every profile (the script's `has_broadcom_wireless` probe holds on every T2 Mac). Carries the `brcmf_awdl` netlink family `t2-drop` needs. |

### Audio

| Upstream sources | Ours |
|---|---|
| `dsp/` (`profiles/`, `config/models.json`, `tools/build.py`, `integration/wireplumber`, `Makefile` `install`) | `dsp/package.nix` (`t2-dsp`: build.py + the Makefile's install layout into `$out`) |
| `scripts/fedora/install-dsp.sh`, `packaging/lifecycle` `configure_dsp_pipewire` | `nix/modules/t2bce-audio-dsp`: udev + WirePlumber from the package, the `model`'s `share/t2-dsp/pipewire/<model>.conf` as `pipewire.conf.d/51-t2-dsp.conf` (replaces the lifecycle's DMI pick), LV2 via `requiredLv2Packages` |
| `modules/t2bce_audio-alsa-ucm-conf/ucm2`, `scripts/fedora/install-alsa-ucm.sh` | `nix/pkgs/t2bce_audio-alsa-ucm-conf` (stock tree + AppleT2 overlay) → `ALSA_CONFIG_UCM2` on pipewire/wireplumber + `environment.variables` |

New `dsp/profiles/<model>` / `models.json` entries → extend the module's `model`
enum + consider a new profile.

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
| `apps/t2-kbd-backlight` (`systemd/t2-kbd-backlight.service`, `config/kbd-backlight.toml`; `install-apps.sh` `has_keyboard_backlight`) | `package.nix` + `nix/modules/t2-kbd-backlight` (config from `settings`; UPower on), on in every profile — took the idle timeout over from `t2-touchbar` |
| `apps/t2-debug` | `package.nix` (source spans the app + `t2-services/shared`; ip/ping on PATH) + `nix/modules/t2-debug`, on in every profile |
| `apps/t2-drop` (`systemd/t2-drop.service`, `dbus/`, `networkmanager/90-t2-drop-awdl.conf`) | `package.nix` + `nix/modules/t2-drop` (Type=dbus unit, ip/nmcli on PATH; Bluetooth on), on in every profile; needs `hardware.kait2en.wireless` |
| `apps/t2-airshare` (`systemd/{t2-airshare,t2-quickshare-hotspot}.service`, `dbus/`, `integration/`) | `package.nix` + `nix/modules/t2-airshare`, on in every profile. **Exception to native units:** the per-user `t2-airshare.service` ships as a file via `systemd.packages`, because the app's receive toggle runs `systemctl --user enable/disable` and needs its `[Install]`. The root hotspot unit is native (iw/ip/nmcli on PATH). `integration/migrate-t2-share.sh` not consumed. |
| `apps/t2-sidecar` (`t2-sidecar{,-sunshine}.service`, `install.sh`) | `package.nix` + `nix/modules/t2-sidecar`, **opt-in** (GNOME-only; inert without the T2-encoder Sunshine fork, which `sunshine.package` supplies) |
| `apps/t2-kernel-builder` | **not ported** — Fedora COPR tooling; our kernel comes from nixpkgs |
| `apps/kait2en-update` (+ `scripts/fedora/update-map`) | **not ported** — the Fedora installer's updater; on NixOS updating is a flake bump |
| `assets/kait2en-app-logo{,-light}.png`, `assets/fonts` (`install-apps.sh` `install_app_assets`) | `nix/pkgs/kait2en-branding` (both wordmarks + JetBrains Mono → `fonts.packages`) + `nix/lib/kait2en-polkit.nix` `rewriteFhsPaths` (rewrites both wordmark paths) |

### t2-services → `t2-services/<name>/package.nix` + `nix/modules/t2-services`

| Upstream sources | Ours |
|---|---|
| `t2-services/shared/{protocols,Makefile}` | `nix/lib/t2-services-src.nix` (crate + `shared/` source filter) |
| `t2-services/shared/integration/{NetworkManager,udev,systemd,libexec/t2-ncm-sleep}`, `scripts/fedora/install-t2-services-common.sh` | `services.t2-services` (NM `10-t2-services.conf` with its keys turned into `+=` appends so it composes with NixOS' main config; the link is unmanaged and brought up by `90-t2-services-ncm.rules` with `ip` from the store; `t2-services-suspend` + sleep.d hook linkFarm) |
| `t2-services/t2-ave` (`integration/systemd`, sleep hook), `scripts/fedora/install-t2-remote.sh` | `package.nix` + `services.t2-ave` |
| `t2-services/t2-touchid` (`integration/{systemd,fprintd,dbus}`, `config/`), `scripts/fedora/install-touchid.sh` | `package.nix` + `services.t2-touchid` (fprintd from `services.fprintd`; SELinux policy not consumed) |
| `t2-services/t2-journal` | `package.nix` only (CLI) |
| `t2-services/t2-autobrightness` (`integration/{systemd,gnome-shell}`), `scripts/fedora/install-autobrightness.sh` | `package.nix` (extension under `share/gnome-shell/extensions`, gsettings on PATH) + `nix/modules/t2-autobrightness` (native user unit), **opt-in** like install.sh `ask_autobrightness` |

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
`configure_dsp_pipewire` semantics above), `apps/deprecated/`, `modules/t2sep`,
`third-party/` (only hex2hcd; unused), `assets/{plymouth,gdm,vornehm}` and the other
logos (the "vornehm" GNOME/Firefox/Ptyxis theme with
`scripts/fedora/install-vornehm.sh`), `scripts/fedora/{acpi-autofix.py, install-acpi-fixes.sh}` (runtime ACPI
table extraction — candidate for a future port),
`scripts/fedora/{install-hardware-video-decoding.sh, install-gdm-branding.sh,
install-plymouth-theme.sh, install-dependencies.sh, build-installer.sh,
kait2en-multicall, lib.sh, install.sh, update-map, install-kernel-source.sh,
install-macos-mount.sh, other/, deprecated/}` (`install-macos-mount.sh` is the
APFS mount helper; apfs is dropped),
`t2-services/*/packaging`,
`t2-services/shared/integration/{migration,libexec/package-actions}`,
`dsp/{tests,packaging,integration/libexec}`,
`patches/{upstream,archived,currently-testing}/**` (opt-in candidates only),
upstream `.github/**`, `PLAN.md`, docs, `LICENSE*`/`LICENSING.md`/`AUTHORS`/
`TRADEMARK.md`/`VALUES.md`.

### Local-only (ours; upstream never touches)

`flake.nix`, `flake.lock`, `nix/**`, `patches/nixos/**`, `skills/**`,
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

(`patches/runtime/gpu-runtime-pm` is upstream's own series, consumed via the GPU
row, not a divergence.)

## Known blockers

- **Build locally against a cached kernel.** The dev Mac builds x86_64-linux
  through the nixham linux-builder, but a kernel build takes hours. Check
  first with `nix path-info --store https://nix.channings.me <kernel.dev>`; if
  the working `flake.lock` pins an uncached kernel, gate against the committed
  lock instead (`--reference-lock-file`). The 2026-11-01 sync gated every
  package and all three toplevels that way (kernel 7.2.11). Opt-in modules
  (`t2-autobrightness`, `t2-sidecar`) are in no profile, so evaluate them via
  `extendModules` on a check system.
- **Hardware-only behaviour of the 2026-11-01 sync**: the unmanaged NCM link
  coming up from udev (t2remote/Touch ID/t2journal reach bridgeOS, and survive
  suspend), AWDL/AirDrop, Quick Share's Bluetooth→hotspot hand-off and Sidecar
  can only be proven on a T2 Mac.
- **Touch Bar config key rename**: `activity_backlight` became
  `activity_escape`; a user `~/.config/kait2en-touchbar/config.toml` still
  carrying the old key makes the daemon refuse to start until renamed by hand
  (upstream's install.sh migrates it; a NixOS module cannot).
- **Keyboard backlight LED rename** (`apple::kbd_backlight` →
  `:white:kbd_backlight`): the saved brightness is lost once after upgrading.

## One-time setup state (done; verify if CI misbehaves)

- The sync job needs repo secrets `FORGE_PAT` and `SIGNING_KEY`; the cache push
  needs `NIKS3_CI_TOKEN`. The cache's public key is
  `garage:JZet/fsItH8cJ6SKLci1+BuMIQGDfZSa/8GxGpKcxss=` (set in the flake's
  `nixConfig`; CI gets it from nixham's `setup-nix-shell`/`niks3-push` actions).
- Upstream's Fedora workflows are **deleted**, not disabled: `origin` is the
  forge (`forge.channings.me/hartlandia/KaiT2en-NixOS`) and GitHub is the
  mirror. Forgejo ignores `.github/workflows` whenever `.forgejo/workflows`
  exists, so only `.forgejo/` runs on the forge.
- `scripts/tests/static-check.sh` (upstream's) asserts on
  `.github/workflows/installer.yml`, which no longer exists here, so that script
  fails on this fork. Nothing in our CI runs it — the gate is `just test` — but
  do not treat its failure as a regression.
