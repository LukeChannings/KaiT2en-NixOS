# t2-ave (`t2remote`): the userspace side of the T2 Apple Video Encoder
# service. It opens the AVE service session on bridgeOS over the NCM link
# (shared t2-bridgexpc transport) and serves /run/t2remote.sock; the kernel side
# is `t2bce_ave`, built with the t2bce stack (modules/default.nix).
#
# Upstream's Makefile also installs integration/systemd/kait2en-t2-remote.service
# (@BINDIR@-templated) and the suspend hook integration/systemd/t2-ave-suspend
# into the shared helper's sleep.d. The unit is defined natively by
# nix/modules/t2-services; the hook is shipped here (wrapped with t2remote +
# coreutils' timeout on PATH) for that module to collect.
{
  lib,
  rustPlatform,
  makeWrapper,
  bash,
  coreutils,
  iproute2,
  iputils,
}:

rustPlatform.buildRustPackage {
  pname = "t2-ave";
  version = "0.1.0";

  src = import ../../nix/lib/t2-services-src.nix { inherit lib; } "t2-ave";
  cargoRoot = "t2-ave";
  buildAndTestSubdir = "t2-ave";
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  postInstall = ''
    # bridgexpc discovery shells out to ip/ping.
    wrapProgram "$out/bin/t2remote" \
      --prefix PATH : ${
        lib.makeBinPath [
          iproute2
          iputils
        ]
      }

    install -Dm755 t2-ave/integration/systemd/t2-ave-suspend \
      "$out/libexec/t2-services/sleep.d/t2-ave"
    patchShebangs "$out/libexec/t2-services/sleep.d/t2-ave"
    wrapProgram "$out/libexec/t2-services/sleep.d/t2-ave" \
      --prefix PATH : "$out/bin:${lib.makeBinPath [ coreutils ]}"
  '';

  meta = {
    description = "Apple T2 AVE (video encoder) service over the bridge link";
    mainProgram = "t2remote";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
