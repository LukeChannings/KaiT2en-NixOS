# t2-journal: a CLI (`t2journal`) that merges Apple T2 bridgeOS unified logs
# with the Linux journal. Moved upstream from apps/t2-journal into
# t2-services/, where it shares the `t2-bridgexpc` transport crate with t2-ave
# and t2-touchid (hence the t2-services-src source helper + cargoRoot).
#
# Plain Rust binary — no GTK, no privileged helper, no system integration. The
# Makefile just `cargo build --release --locked` and installs the binary.
# At runtime it shells out to `journalctl`, and bridgexpc discovery runs
# `ip`/`ping` to find the T2 over the NCM link, so we wrap those onto PATH.
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

  src = import ../../nix/lib/t2-services-src.nix { inherit lib; } "t2-journal";
  cargoRoot = "t2-journal";
  buildAndTestSubdir = "t2-journal";
  cargoLock.lockFile = ./Cargo.lock;

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
    license = lib.licenses.gpl3Plus;
  };
}
