# GPU passthrough: RTX 3080 -> Windows VM, host displays on the iGPU.
# (Replaces nvidia.nix — nothing on the host uses the 3080 anymore.)
#
# PCI IDs captured 2026-07-03 from `lspci -nn`:
#   01:00.0 GPU   10de:2216  (GA102 / RTX 3080 LHR)
#   01:00.1 audio 10de:1aef
# IOMMU group 17 contains exactly these two devices — clean isolation,
# no ACS override hacks needed.
{ config, lib, pkgs, ... }:

{
  # ── IOMMU + early vfio-pci binding ──────────────────────────────────────
  # vfio-pci must claim the 3080 before any graphics driver can; the ids=
  # param plus the initrd modules guarantee that. intel_iommu is already
  # default-on for this kernel, but explicit keeps the requirement visible.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
    "vfio-pci.ids=10de:2216,10de:1aef"
  ];
  # i915 loads in the initrd too (early KMS): the iGPU is the host's only
  # display, and leaving it to udev coldplug races the xe driver — xe can
  # probe device 4680 first, decline it, and i915 never loads at all
  # (hit on 2026-07-03: Hyprland started with zero outputs, black screen).
  boot.initrd.kernelModules = [ "i915" "vfio_pci" "vfio" "vfio_iommu_type1" ];
  # Belt and braces: nothing on the host should ever touch the card.
  boot.blacklistedKernelModules = [ "nouveau" "nvidia" ];

  # ── Virtualization stack ────────────────────────────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    # The NixOS default onShutdown="suspend" (managedsave) is impossible for
    # win11 — VFIO hostdevs + ivshmem + invtsc make it non-migratable — so a
    # host shutdown with the VM up failed the save, SIGKILLed qemu (dirty
    # Windows shutdown), and left the guest flagged "was running" for
    # libvirt-guests to cold-start on the next boot. ACPI-shutdown it instead.
    onShutdown = "shutdown";
    qemu = {
      swtpm.enable = true; # Windows 11 requires a TPM
      # UEFI (OVMF) firmware, incl. secure-boot variants, ships with QEMU by
      # default on 26.05 — pick the secboot .fd in virt-manager when creating
      # the VM. (The old qemu.ovmf options were removed.)
      # Run qemu as z: the Looking Glass shmem is an ivshmem-plain file at
      # /dev/shm/looking-glass, and running qemu as z makes that file z-owned
      # so the LG client (also z) can mmap it. The ACL below is just the qemu
      # default — a plain shm file lives on tmpfs, so needs no device-node ACL.
      verbatimConfig = ''
        # NixOS's own default — verbatimConfig REPLACES it, so it must be
        # restated or libvirt re-enables per-VM /dev namespaces, which are
        # broken on NixOS (VM start fails creating device nodes).
        namespaces = []
        user = "z"
        cgroup_device_acl = [
          "/dev/null", "/dev/full", "/dev/zero",
          "/dev/random", "/dev/urandom",
          "/dev/ptmx", "/dev/kvm",
          "/dev/rtc", "/dev/hpet"
        ]
      '';
    };
  };
  # ── Make qemu.conf changes go live on `nixos-rebuild switch` ─────────────
  # By default they don't: libvirtd-config is a oneshot (RemainAfterExit=no)
  # that NixOS won't re-run on switch, and libvirtd has restartIfChanged=false,
  # so verbatimConfig edits (namespaces, ACLs) land in the store but never reach
  # /var/lib/libvirt/qemu.conf until a reboot or manual `systemctl restart
  # libvirtd`. That drift silently broke Looking Glass once — the VM started
  # under a stale namespace config, so its ivshmem file went to a private
  # /dev/shm the host client couldn't see. Tying both units to the config
  # content makes a switch regenerate the file and reconnect the daemon.
  # A libvirtd restart does NOT kill running domains (qemu lives in its own
  # scope; libvirtd reconnects on start) — they simply adopt the new qemu.conf
  # on their next start, which is exactly when it matters.
  systemd.services.libvirtd-config.restartTriggers = [
    config.virtualisation.libvirtd.qemu.verbatimConfig
  ];
  systemd.services.libvirtd = {
    restartIfChanged = lib.mkForce true; # module pins this false; we want switch to apply qemu.conf
    restartTriggers = [ config.virtualisation.libvirtd.qemu.verbatimConfig ];
  };
  # ── Don't let logind delete the VM's shmem on logout ─────────────────────
  # logind's default RemoveIPC=yes wipes ALL POSIX shm owned by a user when
  # their last session ends — and qemu runs as z (see above), so a session
  # crash/logout unlinks /dev/shm/looking-glass out from under the running VM
  # (happened 2026-07-03 when Hyprland segfaulted: LG couldn't reattach until
  # the VM was power-cycled, since only qemu startup recreates the file).
  services.logind.settings.Login.RemoveIPC = false;
  # ── Host CPU isolation while the VM runs ────────────────────────────────
  # vcpupin only constrains where qemu may run; nothing stops host tasks
  # from preempting the pinned vCPUs. This hook shoves the host onto the
  # E-cores (16-19) for the VM's lifetime — one set-property per unit
  # (systemctl accepts only one), AllowedCPUs="" resets to unrestricted.
  virtualisation.libvirtd.hooks.qemu.isolate = pkgs.writeShellScript "qemu-hook-isolate" ''
    [ "$1" = "win11" ] || exit 0
    case "$2" in
      started)
        for u in system.slice user.slice init.scope; do
          systemctl set-property --runtime "$u" AllowedCPUs=16-19
        done
        ;;
      release)
        for u in system.slice user.slice init.scope; do
          systemctl set-property --runtime "$u" AllowedCPUs=""
        done
        ;;
    esac
  '';

  programs.virt-manager.enable = true;
  users.users.z.extraGroups = [ "libvirtd" ]; # merges with the list in configuration.nix
  # Lets virt-manager hand USB devices to the VM (game controllers etc.)
  virtualisation.spiceUSBRedirection.enable = true;

  # ── Looking Glass shared memory (ivshmem-plain shm file, NOT kvmfr) ──────
  # The VM exposes a plain ivshmem device backed by /dev/shm/looking-glass (see
  # the <shmem> block in the domain XML and docs/win11-vm.md); qemu creates that
  # file on VM start and, running as z (above), makes it z-owned so the LG
  # client can mmap it. Size the XML <size> to width*height*4B*2frames +
  # overhead rounded up to a power of 2: 2560x1440 SDR => ~40 MB => 64;
  # HDR (10-bit) doubles => 128. Nothing is needed here for the shm-file path.
  #
  # kvmfr is deliberately NOT used: on kernel 6.18 VFIO can't DMA-map kvmfr
  # device memory, so qemu SIGABRTs in vfio_container_region_add ~5 s into boot.
  # To retry kvmfr once the module catches up with the kernel, re-add the four
  # lines below and repoint the XML <shmem> at /dev/kvmfr0:
  #   boot.extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
  #   boot.kernelModules = [ "kvmfr" ];
  #   boot.extraModprobeConfig = "options kvmfr static_size_mb=64";
  #   services.udev.extraRules = ''SUBSYSTEM=="kvmfr", OWNER="z", GROUP="kvm", MODE="0660"'';

  # ── Still manual, by design (VM-XML / in-VM / hardware steps) ───────────
  # * VM definition in virt-manager: pass through 01:00.0 + 01:00.1, an
  #   ivshmem-plain <shmem> device (backed by /dev/shm/looking-glass), virtio
  #   disk/net drivers.
  # * Input capture: use Looking Glass's own capture (spice, relative +
  #   input:rawMouse for gaming), NOT evdev. evdev <input type='evdev'>
  #   passthrough was REMOVED 2026-07-03: input-linux opened the NuPhy/Razer
  #   nodes but QEMU silently closed each fd on the first event read (0 open
  #   fds observed across a boot + live QMP object-add), so ctrl-ctrl never
  #   grabbed. It also read every host keystroke (grab='all'), so good riddance.
  #   Remap LG's escape/capture key off ScrollLock (input:escapeKey) — the
  #   Air75 V2 has no ScrollLock.
  # * Error 43: did NOT appear (2026-07-03, current GeForce driver) — no
  #   vendor_id spoof / kvm hidden needed. Add to the XML only if it shows up.
  # * Looking Glass host app inside Windows: install B7 to match the host
  #   client (B7 from nixpkgs). IVSHMEM driver needs a manual
  #   install — the by-hand DISM deploy bypassed the autounattend injection.
  # * Display head for the 3080 (LG needs an active output): DisplayPort to the
  #   G7's 2nd input is preferred (real 1440p240 EDID + native-input fallback);
  #   a dummy plug must be DP/HDMI 2.1 for 240 Hz; a VDD is a software stopgap.
  #   See docs/win11-vm.md.
  #
  # NB: OS was installed via manual DISM apply, not the autounattend — the new
  # 25H2 graphical Setup fails (0xD000A000) because WinPE lacks viostor. See
  # docs/win11-vm.md for the recipe.
}
