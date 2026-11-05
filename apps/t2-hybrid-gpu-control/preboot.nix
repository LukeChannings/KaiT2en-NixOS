# t2-gpu-preboot: the UEFI image upstream (873ac3d) boots before the loader to
# put `gpu-power-prefs` back to the iGPU after macOS has reset it, then warm
# resets so the firmware POSTs on the right GPU. Without a boot GPU to restore
# it just chainloads the real loader.
#
# Two things make this unlike every other app here.
#
# 1. It targets `x86_64-unknown-uefi`, for which nixpkgs' rustc ships no
#    precompiled std (`lib/rustlib` has only bpf, wasm and the host). Fedora
#    installs one (`install.sh`: `dnf install rust-std-static-x86_64-unknown-uefi`);
#    the equivalent here is to build `core`/`alloc`/`compiler_builtins` from
#    source with cargo's `-Z build-std`. That needs nightly, hence
#    RUSTC_BOOTSTRAP, and it needs the std sources plus *their* crates.io
#    dependencies vendored, hence the merged vendor dir below —
#    `rustPlatform.rustLibSrc` carries its own Cargo.lock for exactly that.
#    Dropping all of this is a one-line change the day nixpkgs' rustc gains the
#    target: set `cargoBuildTarget` and delete the rest.
#
# 2. Upstream hardcodes Fedora's loader in `CHAINLOAD` (shimx64, then grubx64),
#    relying on an error return falling through to the next BootOrder entry.
#    That fallthrough would work here too, but it costs a failed image load on
#    every boot, so {option}`chainload` is substituted into the source the same
#    way kait2en-polkit.nix rewrites FHS paths in the GUI's main.rs. Keep it at
#    two entries: the constant is a fixed-size array.
{
  lib,
  stdenv,
  cargo,
  rustc,
  rustPlatform,
  lld,
  runCommand,
  # Backslash-separated UEFI paths, primary loader first. The defaults are
  # systemd-boot and the removable-media fallback every ESP has.
  chainload ? [
    "\\EFI\\systemd\\systemd-bootx64.efi"
    "\\EFI\\BOOT\\BOOTX64.EFI"
  ],
}:

let
  src = lib.cleanSource ./preboot;

  appVendor = rustPlatform.importCargoLock { lockFile = ./preboot/Cargo.lock; };
  # build-std resolves the whole `library` workspace, which reaches crates.io
  # (proc_macro -> rustc-literal-escaper, ...), so vendor the std lock too.
  stdVendor = rustPlatform.importCargoLock {
    lockFile = "${rustPlatform.rustLibSrc}/Cargo.lock";
  };

  # importCargoLock writes a .cargo/config.toml per tree pinning `directory`,
  # so the two cannot simply be stacked: merge the crates and write one config.
  vendor = runCommand "t2-gpu-preboot-vendor" { } ''
    mkdir -p $out
    for tree in ${appVendor} ${stdVendor}; do
      for crate in "$tree"/*; do
        name=$(basename "$crate")
        [ -e "$out/$name" ] || ln -s "$crate" "$out/$name"
      done
    done
    cat > $out/config.toml <<EOF
    [source.crates-io]
    replace-with = "vendored-sources"

    [source.vendored-sources]
    directory = "$out"
    EOF
  '';

  quoted = map (path: ''cstr16!("${lib.replaceStrings [ "\\" ] [ "\\\\" ] path}")'') chainload;
in
assert lib.assertMsg (
  lib.length chainload == 2
) "chainload must have exactly 2 entries: CHAINLOAD is a [&CStr16; 2]";
stdenv.mkDerivation {
  pname = "t2-gpu-preboot";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    cargo
    rustc
    lld # the uefi target links PE with lld in MSVC flavour
  ];

  # -Z build-std is nightly-only; the toolchain is otherwise stock stable.
  RUSTC_BOOTSTRAP = 1;
  __CARGO_TESTS_ONLY_SRC_ROOT = "${rustPlatform.rustLibSrc}";

  postPatch = ''
    substituteInPlace src/main.rs \
      --replace-fail 'cstr16!("\\EFI\\fedora\\shimx64.efi")' '${lib.elemAt quoted 0}' \
      --replace-fail 'cstr16!("\\EFI\\fedora\\grubx64.efi")' '${lib.elemAt quoted 1}'
  '';

  buildPhase = ''
    runHook preBuild
    export CARGO_HOME=$PWD/.cargo-home
    mkdir -p "$CARGO_HOME"
    cp ${vendor}/config.toml "$CARGO_HOME/config.toml"
    cargo build --release --locked --offline \
      --target x86_64-unknown-uefi \
      -Z build-std=core,alloc,compiler_builtins \
      -Z build-std-features=compiler-builtins-mem
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 target/x86_64-unknown-uefi/release/t2-gpu-preboot.efi \
      "$out/share/t2-hybrid-gpu-control/t2-gpu-preboot.efi"
    runHook postInstall
  '';

  # A PE32+ image: nothing here is an ELF to strip, patchelf or RPATH-shrink.
  dontFixup = true;

  meta = {
    description = "UEFI image restoring the integrated boot GPU after macOS";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl3Plus;
  };
}
