# Groups the KaiT2en GUI apps into one folder in the GNOME app grid.
#
# A dconf *system* default can't do this: GNOME writes org.gnome.desktop.app-
# folders folder-children into the user database on first login, which then
# shadows any system default. So a user unit merges the folder into each user's
# existing folder-children at login (appending, never replacing the user's own
# folders) and rewrites the folder's name and app list.
#
# GNOME Shell seeds its stock folders (Utilities, System) only while
# folder-children has no user value, so the unit leaves an unset key alone: on
# a brand-new account the folder appears from the second login.
#
# Each GUI module adds its own desktop ID to `apps` when its app is installed.
#
# Home-manager users have a cleaner route to the same end: ./home-manager.nix
# owns the user database declaratively instead of patching it at login. The two
# sit alongside each other — they write the same keys with the same folder ID,
# so whichever runs last wins and the result is identical. Set `enable = false`
# here if home-manager is doing it.
#
# This module only decides how the installed apps are *presented*. Whether an
# app is installed at all, and whether its daemon runs, stays with that app's
# own `services.<app>.enable`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.kait2en-utilities;
  folderId = "kait2en-utilities";
  dir = "/org/gnome/desktop/app-folders";
in
{
  options.services.kait2en-utilities = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.desktopManager.gnome.enable;
      defaultText = lib.literalExpression "config.services.desktopManager.gnome.enable";
      description = ''
        Whether to group the installed KaiT2en GUI apps into a GNOME app-grid
        folder. With this off the apps are still installed; their entries just
        sit loose in the grid.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "KaiT2en Utilities";
      description = "The folder's display name.";
    };

    apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Desktop IDs placed in the folder. Each KaiT2en GUI module adds its own.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.apps != [ ]) {
    systemd.user.services.kait2en-utilities = {
      description = "Group the KaiT2en apps into a GNOME app folder";
      wantedBy = [ "graphical-session.target" ];
      path = [ pkgs.dconf ];
      serviceConfig.Type = "oneshot";
      script = ''
        children=$(dconf read ${dir}/folder-children)
        case "$children" in
          "") exit 0 ;;
          *"'${folderId}'"*) ;;
          "@as []") dconf write ${dir}/folder-children "['${folderId}']" ;;
          *) dconf write ${dir}/folder-children "''${children%]}, '${folderId}']" ;;
        esac

        dconf write ${dir}/folders/${folderId}/name ${lib.escapeShellArg (toString (lib.gvariant.mkValue cfg.name))}
        dconf write ${dir}/folders/${folderId}/translate false
        dconf write ${dir}/folders/${folderId}/apps ${lib.escapeShellArg (toString (lib.gvariant.mkValue cfg.apps))}
      '';
    };
  };
}
