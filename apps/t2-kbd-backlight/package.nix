# t2-kbd-backlight: the keyboard backlight idle timeout for every T2 MacBook,
# split out of the Touch Bar daemon upstream (fb187c0, 7f497a1). A root daemon:
# libinput watches keyboard, trackpad and Touch Bar input, and the level is
# set through UPower's KbdBacklight so the desktop slider stays in sync.
#
# Upstream's Makefile also installs systemd/t2-kbd-backlight.service
# (hardcodes /usr/local/bin) and seeds /etc/kait2en/kbd-backlight.toml; the
# NixOS module (nix/modules/t2-kbd-backlight) defines the unit natively and
# renders the config from options. The default config ships under
# share/t2-kbd-backlight for reference.
{
  lib,
  rustPlatform,
  pkg-config,
  libinput,
  udev,
}:

rustPlatform.buildRustPackage {
  pname = "t2-kbd-backlight";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libinput
    udev
  ];

  postInstall = ''
    install -Dm644 config/kbd-backlight.toml \
      "$out/share/t2-kbd-backlight/kbd-backlight.toml"
  '';

  meta = {
    description = "Keyboard backlight idle timeout for Apple T2 MacBooks";
    mainProgram = "t2-kbd-backlight";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Plus;
  };
}
