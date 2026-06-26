# Generic builder for the KaiT2en out-of-tree kernel modules.
#
# The in-repo Makefiles each drive `make -C $KDIR M=$PWD modules` (just with
# different variable names for the kernel build dir / release), then their own
# `install` target shells out to `install -o root` + `depmod` into absolute
# `/lib/modules` paths. Those install targets cannot run in the Nix sandbox, so
# we only invoke the build and then collect the produced `.ko` files ourselves
# into `$out/lib/modules/<modDirVersion>/misc/`, the layout NixOS'
# `boot.extraModulePackages` expects.
{
  lib,
  stdenv,
  kmod,
  kernel,
}:

{
  # Module package name (matches the upstream PACKAGE_NAME in dkms.conf).
  pname,
  version,
  src,
  # Extra `make` variables. `KDIR`/`KERNEL_DIR`/`KERNEL_SRC`/`KVER`/`KVERSION`/
  # `KERNEL_RELEASE`/`KERNELRELEASE` are passed automatically below; this is for
  # anything else.
  makeFlags ? [ ],
  nativeBuildInputs ? [ ],
  extraPostPatch ? "",
  meta ? { },
}:

let
  inherit (kernel) modDirVersion;
  kernelBuildDir = "${kernel.dev}/lib/modules/${modDirVersion}/build";
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ kmod ] ++ nativeBuildInputs;

  # Out-of-tree modules build against the kernel's own (already hardened)
  # flags; the default userspace hardening flags break the kbuild.
  hardeningDisable = [
    "pic"
    "format"
  ];

  postPatch = extraPostPatch;

  # Cover every variable name the assorted in-repo Makefiles use to find the
  # kernel build tree and release string, so a single builder fits them all.
  makeFlags = [
    "KDIR=${kernelBuildDir}"
    "KERNEL_DIR=${kernelBuildDir}"
    "KERNEL_SRC=${kernelBuildDir}"
    "KVER=${modDirVersion}"
    "KVERSION=${modDirVersion}"
    "KERNEL_RELEASE=${modDirVersion}"
    "KERNELRELEASE=${modDirVersion}"
  ]
  ++ makeFlags;

  # The Makefiles' `all` target already runs `make … modules`; just let the
  # default `make` (all) run with the flags above.
  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    dest="$out/lib/modules/${modDirVersion}/misc"
    mkdir -p "$dest"

    found=0
    while IFS= read -r -d "" ko; do
      install -Dm644 "$ko" "$dest/$(basename "$ko")"
      found=1
    done < <(find . -name '*.ko' -print0)

    if [ "$found" -eq 0 ]; then
      echo "error: no .ko files were produced by the build" >&2
      exit 1
    fi

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.linux;
  }
  // meta;
}
