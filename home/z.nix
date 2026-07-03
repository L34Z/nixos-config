{ config, pkgs, ... }:

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
  home.stateVersion = "25.11"; # do not change later

  programs.home-manager.enable = true;

  # Polkit auth agent — GUI privilege prompts (gparted, flatpak, etc.)
  # don't work in a bare Hyprland session without one. Starts with
  # graphical-session.target, which exists because of UWSM.
  services.hyprpolkitagent.enable = true;

  # ── Personal apps: minimal viable set ────────────────────────────────────
  # (1Password is system-level in configuration.nix for polkit/ssh-agent.)
  home.packages = with pkgs; [
    firefox
    claude-code

    # Deferred — uncomment as needed once the base system is solid:
    # discord
    # stremio
    # anytype
    # notesnook
    # vscode
    # zen-browser?   # check packaging state; was rough on linux before
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
  xdg.configFile."waybar".source = ./dotfiles/waybar;
  xdg.configFile."kitty".source = ./dotfiles/kitty;

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
