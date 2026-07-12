if status is-interactive
    # Commands to run in interactive sessions can go here
end



set -U fish_greeting

# Route SSH (and ssh-add, git, etc.) to the 1Password SSH agent
set -gx SSH_AUTH_SOCK $HOME/.1password/agent.sock

oh-my-posh init fish --config ~/.config/fish/tokyonight_storm.omp.json | source
source ~/.config/fish/aliases.fish
zoxide init fish | source
direnv hook fish | source

# (tty autostart removed: greetd/tuigreet on tty1 now launches the session —
# Hyprland via uwsm or niri via niri-session; see modules/greeter.nix)
