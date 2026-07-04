{ config, pkgs, inputs, ... }:

let
  # The repo is expected to live at ~/nixos on the installed system.
  # hypr + fish are linked "out of store" so you can edit them live
  # (SUPER+ALT+H etc.) without a rebuild. Everything else is store-managed.
  repo = "${config.home.homeDirectory}/nixos";
  live = path: config.lib.file.mkOutOfStoreSymlink "${repo}/${path}";
in
{
  home.username = "z";
  home.homeDirectory = "/home/z";
  home.stateVersion = "26.05"; # do not change later

  programs.home-manager.enable = true;

  # ── Cursor ───────────────────────────────────────────────────────────────
  # Without a theme installed Hyprland falls back to the bare X11 pointer.
  # This installs Bibata and wires up XCURSOR (x11), GTK, and hyprcursor at
  # once. This is the SINGLE source of the cursor theme/size for the session:
  # it exports XCURSOR_*/HYPRCURSOR_*, so hyprland.lua no longer sets them.
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };

  # Polkit auth agent — GUI privilege prompts (gparted, flatpak, etc.)
  # don't work in a bare Hyprland session without one. Starts with
  # graphical-session.target, which exists because of UWSM.
  services.hyprpolkitagent.enable = true;

  # ── Caelestia shell ──────────────────────────────────────────────────────
  # Quickshell-based shell: bar + launcher + notifications + OSD + session
  # menu. Replaces waybar/rofi/swaync/hyprpaper. Module comes from the
  # caelestia-shell flake input (wired in via home-manager.sharedModules).
  # Keybinds stay in hyprland.lua: the shell only *registers* global
  # shortcuts (caelestia:launcher etc.); nothing is bound unless we bind it.
  programs.caelestia = {
    enable = true;
    # QML overrides, swapped in at install time. The QML is installed as
    # plain files, so this only re-runs the cheap install step — the C++
    # plugin derivations are reused as-is.
    #  - ColourSelect: upstream's nexus "Colours" sub-page is an
    #    under-construction stub; replace it with our colour editor.
    #  - ActiveWindow: bar window title in m3onPrimary instead of m3primary.
    package = inputs.caelestia-shell.packages.${pkgs.system}.with-cli.overrideAttrs (prev: {
      postInstall = (prev.postInstall or "") + ''
        install -Dm644 ${./dotfiles/caelestia/nexus/ColourSelect.qml} \
          $out/share/caelestia-shell/modules/nexus/pages/wallandstyle/ColourSelect.qml
        install -Dm644 ${./dotfiles/caelestia/bar/ActiveWindow.qml} \
          $out/share/caelestia-shell/modules/bar/components/ActiveWindow.qml
      '';
    });
    # Started from hyprland.lua's autostart like every other session process,
    # not as a systemd unit — keeps startup logic in one place.
    systemd.enable = false;
    cli.enable = true; # `caelestia` command (shell IPC, wallpaper, etc.)
    # NO `settings` here on purpose: the module renders settings as a read-only
    # store symlink at ~/.config/caelestia/shell.json, but the shell writes its
    # config back at runtime (nexus settings app, config plugin) and spams
    # "Failed to write: Read-only file system" otherwise. shell.json is kept as
    # a plain mutable file instead; seed copy in home/dotfiles/caelestia/.
  };

  # ── Personal apps: minimal viable set ────────────────────────────────────
  # (1Password is system-level in configuration.nix for polkit/ssh-agent.)
  home.packages = with pkgs; [
    firefox
    claude-code
    looking-glass-client # the Windows VM's screen, as a window (see modules/vfio.nix)
    hyprpicker # screen colour picker; the nexus Colours page shells out to it

    # Deferred — uncomment as needed once the base system is solid:
    discord
    stremio-linux-shell
    # anytype
    # notesnook
    # vscode
    # zen-browser  # check packaging state; was rough on linux before
    # qalculate-gtk
    # polychromatic  # needs hardware.openrazer.enable in configuration.nix
    # filezilla
    # waypaper
    # rofimoji
  ];

  # ── Dotfiles ─────────────────────────────────────────────────────────────
  # Live-editable (symlink into the repo working tree):
  xdg.configFile."hypr".source = live "home/dotfiles/hypr";
  xdg.configFile."fish".source = live "home/dotfiles/fish";

  # Store-managed (edit in repo, then rebuild):
  xdg.configFile."kitty".source = ./dotfiles/kitty;
  # (waybar link removed with the caelestia migration; home/dotfiles/waybar
  # kept in the repo for reference/rollback)

  # ── SSH via 1Password agent ──────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      extraOptions.IdentityAgent = "~/.1password/agent.sock";
    };
  };

  # ── Git (was unset in the old config; fill in your email) ───────────────
  programs.git = {
    enable = true;
    # fill these in locally after install:
    # settings.user.name = "";
    # settings.user.email = "";
    # To sign commits with the 1Password SSH key, we can wire
    # gpg.format = "ssh" + signingkey later.
  };
}
