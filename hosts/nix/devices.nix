# Which physical disk gets which role. install.sh rewrites this file
# interactively at install time after showing you lsblk — these are
# just likely defaults, never trusted blindly.
{
  system = "/dev/nvme0n1"; # NixOS: EFI + LUKS root (the NVMe)
  storage = "/dev/sda"; # data: LUKS + btrfs (the 2TB SSD)
}
