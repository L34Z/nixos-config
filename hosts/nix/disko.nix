# Declarative disk layout, applied by disko during install (see install.sh).
# Device paths live in devices.nix, which install.sh writes after prompting.
let
  devices = import ./devices.nix;
in
{
  disko.devices = {
    disk = {
      # System drive: NVMe. EFI + one big LUKS2 container, btrfs subvolumes inside.
      system = {
        type = "disk";
        device = devices.system;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # install.sh writes your passphrase here so disko can format
                # non-interactively. Lives only in the installer's RAM.
                passwordFile = "/tmp/luks-root.pass";
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          };
        };
      };

      # Storage drive: 2TB SSD. LUKS2 unlocked after boot via keyfile that
      # lives on the (already unlocked) encrypted root. One passphrase at boot.
      storage = {
        type = "disk";
        device = devices.storage;
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptstorage";
                # Unlock via /etc/crypttab after root is mounted, not in initrd.
                initrdUnlock = false;
                settings = {
                  keyFile = "/etc/cryptkey";
                  allowDiscards = true;
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@storage" = {
                      mountpoint = "/storage";
                      mountOptions = [ "compress=zstd" "noatime" "nofail" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
