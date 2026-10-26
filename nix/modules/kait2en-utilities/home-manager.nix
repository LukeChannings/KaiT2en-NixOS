# Home-manager module: groups the KaiT2en GUI apps into one folder in the
# GNOME app grid, declaratively.
#
# This is the same end as the NixOS module next door (./default.nix), reached
# the right way round. GNOME writes org.gnome.desktop.app-folders into the
# *user* dconf database, where it shadows any system default — so the NixOS
# module has to patch that database from a login-time user unit. Home-manager
# owns the user database already (`dconf.settings`, applied at activation), so
# here the folder is just configuration.
#
# The two modules sit alongside each other and write the same keys under the
# same folder ID, so having both on is harmless; whichever applies last leaves
# the same result. If you want only this one, set
# `services.kait2en-utilities.enable = false` on the NixOS side.
#
# Unlike the login-time unit, `dconf.settings` *replaces* folder-children
# rather than appending to it — a declarative key has one value. So the folders
# the grid should list are spelled out in `folderChildren`: the stock GNOME
# "Utilities" folder plus our own, which is a separate folder named "KaiT2en
# Utilities" (the stock one is left alone). Any folder you keep outside that
# list needs adding to it, or it will stop being listed.
#
# Turning `enable` off removes the folder: folder-children is written without
# it and the app entries go back to sitting loose in the grid. The apps
# themselves are untouched — what is installed, and whether its daemon runs, is
# the NixOS side's business.
{
  config,
  lib,
  osConfig ? null,
  ...
}:

let
  cfg = config.services.kait2en-utilities;
  folderId = "kait2en-utilities";
  dir = "org/gnome/desktop/app-folders";

  # Every KaiT2en GUI app's desktop ID — mirrors the IDs the NixOS modules
  # each contribute to `services.kait2en-utilities.apps` as they install their
  # app (nix/modules/t2-*/default.nix). Used only as the standalone fallback;
  # listing an app that is not installed is harmless, GNOME ignores entries it
  # cannot resolve.
  allApps = [
    "org.t2fancontrol.gtk.desktop"
    "org.t2smccontrol.gtk.desktop"
    "org.t2forceclick.gtk.desktop"
    "org.t2powertune.gtk.desktop"
    "org.t2powerexplorer.gtk.desktop"
    "org.t2zonepower.gtk.desktop"
    "org.t2hybridgpucontrol.gtk.desktop"
    "org.t2dgpucontrol.gtk.desktop"
  ];

  # Run as a NixOS-integrated home-manager (`home-manager.users.<name>`) and
  # the host's config is visible as `osConfig`, which knows exactly which GUI
  # apps this machine installs — so follow it. Standalone there is no such
  # view: list them all.
  inherited = osConfig.services.kait2en-utilities.apps or null;

  # With nothing to put in it, there is no folder to make.
  wanted = cfg.enable && cfg.apps != [ ];
in
{
  options.services.kait2en-utilities = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to group the KaiT2en GUI apps into a GNOME app-grid folder.
        With this off the folder is removed and the app entries sit loose in
        the grid; the apps stay installed either way.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "KaiT2en Utilities";
      description = "The folder's display name.";
    };

    folderChildren = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Utilities"
        folderId
      ];
      defaultText = lib.literalExpression ''[ "Utilities" "${folderId}" ]'';
      description = ''
        The complete list of app-grid folders, written to
        org.gnome.desktop.app-folders folder-children. Declarative, hence
        complete: add any folder of your own you want to keep listed. The
        default is GNOME's stock "Utilities" plus the KaiT2en folder.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = if inherited != null then inherited else allApps;
      defaultText = lib.literalExpression ''
        the host's `services.kait2en-utilities.apps` when home-manager runs as a
        NixOS module, otherwise every KaiT2en GUI app's desktop ID
      '';
      description = "Desktop IDs placed in the folder.";
    };
  };

  config.dconf.settings = lib.mkMerge [
    (lib.mkIf wanted {
      "${dir}".folder-children = cfg.folderChildren;
      "${dir}/folders/${folderId}" = {
        inherit (cfg) name;
        translate = false;
        inherit (cfg) apps;
      };
    })
    (lib.mkIf (!wanted) {
      "${dir}".folder-children = lib.filter (child: child != folderId) cfg.folderChildren;
    })
  ];
}
