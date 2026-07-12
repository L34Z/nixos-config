# greetd + tuigreet: minimal console-style login greeter.
# F2 opens the session picker, F3 toggles the power menu. Sessions come from
# services.displayManager.sessionPackages — Hyprland/UWSM (desktop.nix) and
# niri (niri.nix) register themselves there, so both show up automatically.
{ config, pkgs, ... }:

let
  # The hyprland package also ships a plain (non-UWSM) hyprland.desktop.
  # Launching that one skips graphical-session.target, so hypridle/polkit
  # never start — hide it and offer only Hyprland (UWSM) + niri.
  sessions = pkgs.runCommand "greeter-sessions" { } ''
    mkdir -p $out
    for f in ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/*.desktop; do
      [ "$(basename "$f")" = hyprland.desktop ] && continue
      ln -s "$f" $out/
    done
  '';
in
{
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = builtins.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember" # last user
        "--remember-user-session" # last session, per user
        "--sessions ${sessions}"
      ];
      user = "greeter";
    };
  };

  # tuigreet persists the --remember state here; nothing creates it for us.
  systemd.tmpfiles.rules = [ "d /var/cache/tuigreet 0755 greeter greeter -" ];
}
