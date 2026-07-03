# nixos config

NixOS 25.11, Hyprland, home-manager, disko-managed disks, full-disk encryption.

## layout

```
flake.nix                    inputs: nixpkgs 25.11, home-manager, disko
install.sh                   run from the installer ISO; does the whole install
hosts/nix/
  configuration.nix          system: boot, plymouth, audio, bluetooth, users
  disko.nix                  disks: NVMe (LUKS+btrfs root), 2TB SSD (LUKS+keyfile)
  hardware-configuration.nix placeholder, regenerated at install
modules/
  desktop.nix                hyprland, waybar, swaync, hyprpaper, hyprlock/idle
  nvidia.nix                 open kernel module, stable driver
home/
  z.nix                      personal apps (MVP set; rest commented), ssh, git
  dotfiles/                  hypr, waybar, fish, kitty configs
```

## encryption

- NVMe: one LUKS2 container, btrfs subvols (@, @home, @nix, @log). Passphrase
  at boot, plymouth prompt.
- 2TB SSD: LUKS2, auto-unlocked after root via keyfile at /etc/cryptkey
  (root-only perms, lives on the encrypted root). Backup passphrase also
  enrolled at install. Mounts at /storage.

## day-2

- Rebuild: `nh os switch ~/nixos`
- hypr and fish dotfiles are out-of-store symlinks: edits apply live, no
  rebuild. waybar/kitty need a rebuild. Repo must live at `~/nixos`.
- Update: `nix flake update && nh os switch ~/nixos`

## deferred (commented in the configs, flip on when ready)

libvirtd + virt-manager, GPU passthrough, openrazer/polychromatic, mullvad,
zen browser, discord/stremio/anytype/notesnook/vscode, the old pywal
theming pipeline (dropped for a static tokyo-night theme).

## post-install checklist

1. `passwd z` via nixos-enter (install.sh reminds you)
2. 1Password: sign in, Settings -> Developer -> Use SSH agent
3. drop a wallpaper at ~/Pictures/wallpaper.png (hyprpaper expects it)
4. `git -C ~/nixos remote add origin <url>` and push
