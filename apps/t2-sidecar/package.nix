# t2-sidecar: an extended GNOME display for streaming the desktop to a tablet,
# the counterpart of macOS Sidecar. `t2-sidecar on|off|status` (Python + Gio)
# starts/stops the user unit that runs `t2-sidecar-display`, which holds a
# Mutter virtual monitor (org.gnome.Mutter.ScreenCast.RecordVirtual). The T2
# encodes the stream through t2bce_sidecar (built with the t2bce stack).
#
# Mirrors install.sh: t2-sidecar → bin, t2-sidecar-display → libexec. The two
# user units (t2-sidecar.service, t2-sidecar-sunshine.service) hardcode
# /usr/local and are defined natively by nix/modules/t2-sidecar. Both scripts
# run `python3 -I`; patchShebangs points them at a python carrying
# pygobject, and the GI wrapper supplies the Gio/GLibUnix typelibs plus
# `systemctl` (for `systemctl --user`) on PATH.
{
  lib,
  stdenvNoCC,
  python3,
  gobject-introspection,
  wrapGAppsNoGuiHook,
  glib,
  systemd,
}:

let
  python = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenvNoCC.mkDerivation {
  pname = "t2-sidecar";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsNoGuiHook
  ];

  buildInputs = [
    python
    glib
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 t2-sidecar "$out/bin/t2-sidecar"
    install -Dm755 t2-sidecar-display "$out/libexec/t2-sidecar-display"
    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ systemd ]})
  '';

  meta = {
    description = "Sidecar-style extended GNOME display for streaming to a tablet through the T2 encoder";
    mainProgram = "t2-sidecar";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
