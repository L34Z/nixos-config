#!/usr/bin/env bash
# NixOS install runbook. Run from the NixOS installer ISO (graphical is fine,
# open a terminal), as root, from inside this repo directory.
#
#   sudo -i
#   git clone <this repo> nixos && cd nixos   # or copy it in via USB
#   bash install.sh
#
# DESTROYS both target disks. Read the prompts.
set -euo pipefail

# some installer images don't have flakes enabled in nix.conf
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# ── 1. Pick target disks (writes hosts/nix/devices.nix) ───────────────────
echo "== Disks on this machine =="
lsblk -dno NAME,SIZE,MODEL | grep -Ev '^(loop|sr|zram)'
echo
read -rp "SYSTEM disk — gets NixOS, will be WIPED (e.g. nvme0n1): " sys
read -rp "STORAGE disk — the 2TB data SSD, will be WIPED (e.g. sda): " sto
SYS="/dev/${sys#/dev/}"
STO="/dev/${sto#/dev/}"
[ -b "$SYS" ] || { echo "$SYS is not a block device"; exit 1; }
[ -b "$STO" ] || { echo "$STO is not a block device"; exit 1; }
[ "$SYS" != "$STO" ] || { echo "System and storage must be different disks"; exit 1; }

cat > hosts/nix/devices.nix <<EOF
# Written by install.sh on $(date -u +%Y-%m-%d) — disk role assignment.
{
  system = "$SYS";
  storage = "$STO";
}
EOF

echo
echo "  SYSTEM  -> $SYS  ($(lsblk -dno SIZE,MODEL "$SYS"))"
echo "  STORAGE -> $STO  ($(lsblk -dno SIZE,MODEL "$STO"))"
echo
read -rp "Both disks above will be COMPLETELY ERASED. Type WIPE to continue: " ok
[ "$ok" = "WIPE" ] || { echo "Aborted, nothing touched."; exit 1; }

# ── 2. Root LUKS passphrase (used by disko to format) ─────────────────────
while :; do
  read -rsp "LUKS passphrase for the system drive: " p1; echo
  read -rsp "Again: " p2; echo
  [ "$p1" = "$p2" ] && [ -n "$p1" ] && break
  echo "Mismatch or empty, try again."
done
printf '%s' "$p1" > /tmp/luks-root.pass

# ── 3. Keyfile for the storage drive ───────────────────────────────────────
# Created here so disko can enroll it at format time; copied onto the
# encrypted root in step 5 so crypttab finds it at /etc/cryptkey on boot.
if [ ! -f /etc/cryptkey ]; then
  dd if=/dev/urandom of=/etc/cryptkey bs=512 count=4 iflag=fullblock
  chmod 400 /etc/cryptkey
fi

# ── 4. Partition, format, mount everything (DESTRUCTIVE) ──────────────────
nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- \
  --mode destroy,format,mount ./hosts/nix/disko.nix

# ── 5. Keyfile onto the encrypted root + a backup passphrase on storage ───
mkdir -p /mnt/etc
cp /etc/cryptkey /mnt/etc/cryptkey
chmod 400 /mnt/etc/cryptkey
echo "Adding a backup passphrase to the storage drive (in case the keyfile"
echo "is ever lost — e.g. the NVMe dies). Pick something you can recover."
# disko labels partitions disk-<name>-<part>, so this path is stable:
cryptsetup luksAddKey --key-file /etc/cryptkey /dev/disk/by-partlabel/disk-storage-luks

# ── 6. Hardware config (no filesystems; disko owns those) ─────────────────
nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/nix/hardware-configuration.nix
rm -rf /mnt/etc/nixos
git add -A   # flakes only see tracked files

# ── 7. Install ─────────────────────────────────────────────────────────────
nixos-install --flake .#nix

rm -f /tmp/luks-root.pass

# ── 8. Persist the repo into the new system ────────────────────────────────
mkdir -p /mnt/home/z
cp -r "$REPO_DIR" /mnt/home/z/nixos
chown -R 1000:100 /mnt/home/z/nixos

echo
echo "Done. Set z's password: nixos-enter --root /mnt -c 'passwd z'"
echo "Then reboot. After boot: 1Password -> Settings -> Developer ->"
echo "enable SSH agent. Rebuild later with: nh os switch ~/nixos"
