# niri + DankMaterialShell: the second session, selectable from the greeter
# alongside Hyprland/caelestia. The nixpkgs module registers the session file,
# sets up portals (gnome/gtk) and gnome-keyring, and wires the systemd session
# units — niri-session handles graphical-session.target natively, no UWSM.
# DMS itself is home-manager (home/z.nix); niri's config.kdl spawns it.
{ pkgs, ... }:

{
  programs.niri.enable = true;

  # DMS settings page reads user info (name/avatar) via AccountsService.
  services.accounts-daemon.enable = true;

  # niri auto-spawns xwayland-satellite from PATH for X11 apps.
  environment.systemPackages = [ pkgs.xwayland-satellite ];
}
