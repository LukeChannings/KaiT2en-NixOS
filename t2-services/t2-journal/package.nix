# t2-journal: a CLI (`t2journal`) that merges Apple T2 bridgeOS unified logs
# with the Linux journal.
#
# Plain Rust binary — no GTK, no privileged helper, no polkit, no system
# integration. The in-repo Makefile just `cargo build --release --locked` and
# installs the binary; rustPlatform reproduces that. At runtime it shells out to
# `journalctl` (and `ip`/`ping` for remote bridgeOS discovery), so we wrap it
# with those on PATH regardless of the caller's environment.
#
# The vendored `macos-unifiedlogs` crate is a path dependency (see Cargo.toml)
# and pulls only crates.io deps, so cargoLock needs no git outputHashes.
{
  lib,
  rustPlatform,
  makeWrapper,
  systemd,
  iproute2,
  iputils,
}:

rustPlatform.buildRustPackage {
  pname = "t2-journal";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  # The Makefile builds `--locked`; keep that guarantee.
  cargoBuildFlags = [ "--locked" ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/t2journal" \
      --prefix PATH : ${
        lib.makeBinPath [
          systemd
          iproute2
          iputils
        ]
      }
  '';

  meta = {
    description = "Merge Apple T2 bridgeOS unified logs with the Linux journal";
    mainProgram = "t2journal";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
