# The KaiT2en app branding, exposed as a store path.
#
# Mirrors scripts/fedora/install-apps.sh `install_app_assets`:
#   * the wordmark — upstream installs `assets/kait2en-app-logo.png` as
#     /usr/local/share/kait2en/kait2en-wordmark.png. The GUI apps load that
#     path at startup (some via a fatal Pixbuf::from_file().expect()); on NixOS
#     there is no /usr/local, so each app `substituteInPlace`s the hardcoded path
#     to this store copy instead.
#   * the bundled JetBrains Mono (`install_kait2en_fonts`), which the apps'
#     CSS names. Installed under share/fonts so `fonts.packages` picks it up
#     (the aggregate NixOS module adds this package when KaiT2en is enabled).
{ runCommand }:

runCommand "kait2en-branding" { } ''
  install -Dm644 ${../../../assets/kait2en-app-logo.png} \
    "$out/share/kait2en/kait2en-wordmark.png"
  install -Dm644 -t "$out/share/fonts/truetype/kait2en" \
    ${../../../assets/fonts/JetBrainsMono-Regular.ttf} \
    ${../../../assets/fonts/JetBrainsMono-Medium.ttf}
  install -Dm644 ${../../../assets/fonts/OFL.txt} \
    "$out/share/licenses/kait2en-fonts/OFL.txt"
''
