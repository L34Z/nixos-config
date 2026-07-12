# Steam, with the whole Steam data dir (client + games) living on the
# storage SSD. ~/.local/share/Steam is a symlink to /storage/games/steam
# (see home/z.nix), so games install there without any Steam UI setup.
# /storage is unlocked via crypttab with nofail — if the drive is ever
# absent, Steam just won't start; boot is unaffected.
#
# GPU: the desktop runs on the iGPU; games should render on the 3080 via
# PRIME offload (modules/nvidia-hybrid.nix). Per-game launch options:
#   gamemoderun nvidia-offload %command%
# Without nvidia-offload a game renders on the iGPU — fine for 2D/indie,
# wrong for anything heavy. Not usable while the win11 VM holds the card.
{ pkgs, ... }:

{
  programs.steam = {
    enable = true; # also pulls in 32-bit graphics/audio support
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # GE-Proton: community Proton build; pick it per-game under
    # Properties → Compatibility when stock Proton misbehaves.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  # `gamemoderun %command%` in a game's launch options for CPU/GPU governor
  # tweaks while the game runs.
  programs.gamemode.enable = true;

  # /storage/games is created root-owned by the mount; hand it to z and
  # pre-create the Steam data dir the home-manager symlink points at.
  systemd.tmpfiles.rules = [
    "d /storage/games 0755 z users -"
    "d /storage/games/steam 0755 z users -"
  ];
}
