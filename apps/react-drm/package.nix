# react-drm: the mandatory Touch Bar runtime. A React renderer targeting Linux
# DRM/KMS through a node-gyp native addon (libdrm + Cairo + librsvg + pango),
# plus the `linux-touchbar-control-center` workspace that drives it.
#
# The upstream install.sh copies the tree into the user's home, runs
# `npm install` + `npm run build` (node-gyp native build, then `tsc`), and
# installs the systemd user unit + udev rules from system/. Here we build the
# whole npm workspace with buildNpmPackage (native addon included) and ship the
# compiled tree plus those system/ assets under $out.
{
  lib,
  buildNpmPackage,
  nodejs,
  python3,
  pkg-config,
  libdrm,
  cairo,
  pango,
  librsvg,
  udev,
  freetype,
  pixman,
}:

buildNpmPackage {
  pname = "react-drm";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  # node-gyp drives the C++ addon (binding.gyp) against the system DRM/Cairo
  # stack; npmDepsHash pins the fetched npm closure. Refresh it with
  #   prefetch-npm-deps apps/react-drm/package-lock.json
  # (or set to lib.fakeHash and copy the value Nix prints on first build).
  npmDepsHash = "sha256-nCPPZ1GxmppDZ091V4usr5tIrc/wo50XiK++XZPcShM=";

  nativeBuildInputs = [
    nodejs
    python3
    pkg-config
  ];

  buildInputs = [
    libdrm
    cairo
    pango
    librsvg
    udev
    freetype
    pixman
  ];

  # binding.gyp hardcodes Fedora include paths (/usr/include/libdrm, …). Strip
  # them; the real include dirs come from NIX_CFLAGS_COMPILE below (the
  # cc-wrapper node-gyp invokes honours it), pointing at the Nix buildInputs'
  # header dirs — libdrm's drm.h lives under include/libdrm, etc.
  postPatch = ''
    substituteInPlace binding.gyp \
      --replace-quiet '"/usr/include/libdrm",' "" \
      --replace-quiet '"/usr/include/cairo",' "" \
      --replace-quiet '"/usr/include/freetype2",' "" \
      --replace-quiet '"/usr/include/pixman-1",' ""
  '';

  NIX_CFLAGS_COMPILE = [
    "-I${lib.getDev libdrm}/include/libdrm"
    "-I${lib.getDev cairo}/include/cairo"
    "-I${lib.getDev freetype}/include/freetype2"
    "-I${lib.getDev pixman}/include/pixman-1"
  ];

  # Build both the native addon and the TypeScript (top-level `build` runs
  # build:native then build:ts; the workspace adds the control-center tsc).
  npmBuildScript = "build";

  # The root `build` only compiles the parent package (src/ -> dist/src/). The
  # systemd user service runs linux-touchbar-control-center/dist/index.js, which
  # is produced by the *workspace's* own `tsc -p tsconfig.json` — the root build
  # never runs it, so without this step that file is missing and the unit
  # crash-loops with MODULE_NOT_FOUND. Compile the workspace here against its
  # tsconfig (typescript is an installed devDependency in node_modules/.bin).
  postBuild = ''
    node_modules/.bin/tsc -p linux-touchbar-control-center/tsconfig.json
  '';

  # buildNpmPackage's default install expects a `bin`/`files`; this is a
  # private app tree, so copy the built workspace + system assets ourselves.
  dontNpmInstall = true;
  installPhase = ''
    runHook preInstall

    appdir="$out/lib/react-drm"
    mkdir -p "$appdir"
    cp -r . "$appdir/"

    # The systemd user unit and udev rules shipped under system/.
    install -Dm644 system/react-drm.service \
      "$out/share/react-drm/system/react-drm.service"
    install -Dm644 system/99-react-drm.rules \
      "$out/share/react-drm/system/99-react-drm.rules"
    install -Dm755 system/react-drm-tb-detach \
      "$out/share/react-drm/system/react-drm-tb-detach"

    runHook postInstall
  '';

  meta = {
    description = "React renderer for the T2 Touch Bar via Linux DRM/KMS";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl3Plus;
  };
}
