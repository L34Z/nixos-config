# Hyprland + the minimal set of desktop daemons:
# waybar (bar), swaync (notifications), hyprpaper (wallpaper),
# hyprlock/hypridle (lock + idle). Nothing else.
{ config, pkgs, ... }:

{
  # Mesa/i915 for the iGPU (UHD 770) — the host's only GPU now that the
  # 3080 is passed through (vfio.nix). Was previously set in nvidia.nix.
  hardware.graphics.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    # UWSM wraps the session in systemd so graphical-session.target activates.
    # Without it, hypridle/polkit-agent user services never start when
    # launching from a tty. fish runs `uwsm start` accordingly.
    withUWSM = true;
  };

  programs.hyprlock.enable = true;
  services.hypridle.enable = true;
  # (polkit agent is a home-manager service; see home/z.nix)

  # portal-hyprland covers screenshare; gtk portal adds file-picker dialogs
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  programs.thunar.enable = true;

  environment.systemPackages = with pkgs; [
    kitty
    waybar
    swaynotificationcenter
    hyprpaper
    rofi # rofi-wayland was merged into rofi in 25.11
    pavucontrol
    pamixer
    playerctl
    wev
    wtype
    ranger
    grim # screenshots
    slurp # region select for grim
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1"; # electron apps -> native wayland
    MOZ_ENABLE_WAYLAND = "1";
    EZA_ICONS_AUTO = "always";
  };
}
