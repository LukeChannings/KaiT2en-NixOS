# The KaiT2en wordmark, exposed as a store path.
#
# The GUI apps load /usr/local/share/kait2en/kait2en-wordmark.png at startup
# (some via a fatal Pixbuf::from_file().expect()). On Fedora install-apps.sh
# drops the PNG there; on NixOS there is no writable /usr/local, so each app
# `substituteInPlace`s that hardcoded path to this store copy instead. The PNG
# is the same asset the website ships.
{ runCommand }:

runCommand "kait2en-branding" { } ''
  install -Dm644 ${../../../website/static/img/kait2en-wordmark.png} \
    "$out/share/kait2en/kait2en-wordmark.png"
''
