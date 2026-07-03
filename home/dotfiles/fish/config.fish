if status is-interactive
    # Commands to run in interactive sessions can go here
end



set -U fish_greeting
oh-my-posh init fish --config ~/.config/fish/tokyonight_storm.omp.json | source
source ~/.config/fish/aliases.fish
zoxide init fish | source
direnv hook fish | source

# Start Hyprland (via uwsm, so systemd user services come up) on tty1 login
if uwsm check may-start
    exec uwsm start hyprland-uwsm.desktop
end
