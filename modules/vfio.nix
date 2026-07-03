# GPU passthrough: RTX 3080 -> Windows VM, host displays on the iGPU.
# (Replaces nvidia.nix — nothing on the host uses the 3080 anymore.)
#
# PCI IDs captured 2026-07-03 from `lspci -nn`:
#   01:00.0 GPU   10de:2216  (GA102 / RTX 3080 LHR)
#   01:00.1 audio 10de:1aef
# IOMMU group 17 contains exactly these two devices — clean isolation,
# no ACS override hacks needed.
{ config, pkgs, ... }:

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
    qemu = {
      swtpm.enable = true; # Windows 11 requires a TPM
      # UEFI (OVMF) firmware, incl. secure-boot variants, ships with QEMU by
      # default on 26.05 — pick the secboot .fd in virt-manager when creating
      # the VM. (The old qemu.ovmf options were removed.)
      # Run qemu as z: gives the VM process access to /dev/kvmfr0 (Looking
      # Glass) now and /dev/input/* (evdev passthrough) later without
      # per-device permission fights. The device ACL is the qemu default
      # plus kvmfr0.
      verbatimConfig = ''
        user = "z"
        cgroup_device_acl = [
          "/dev/null", "/dev/full", "/dev/zero",
          "/dev/random", "/dev/urandom",
          "/dev/ptmx", "/dev/kvm",
          "/dev/kvmfr0"
        ]
      '';
    };
  };
  programs.virt-manager.enable = true;
  users.users.z.extraGroups = [ "libvirtd" ]; # merges with the list in configuration.nix
  # Lets virt-manager hand USB devices to the VM (game controllers etc.)
  virtualisation.spiceUSBRedirection.enable = true;

  # ── Looking Glass shared memory (kvmfr) ─────────────────────────────────
  # DMA-capable framebuffer shared between the VM's 3080 and the host client.
  # Size: width*height*4bytes*2frames + overhead, rounded up to a power of 2.
  # 2560x1440 SDR => ~40 MB => 64. If Windows drives the G7 in HDR (10-bit),
  # frames double => bump to 128.
  boot.extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
  boot.kernelModules = [ "kvmfr" ];
  boot.extraModprobeConfig = ''
    options kvmfr static_size_mb=64
  '';
  services.udev.extraRules = ''
    SUBSYSTEM=="kvmfr", OWNER="z", GROUP="kvm", MODE="0660"
  '';

  # ── Still manual, by design (VM-XML / in-VM / hardware steps) ───────────
  # * VM definition in virt-manager: pass through 01:00.0 + 01:00.1, ivshmem
  #   device pointing at /dev/kvmfr0, virtio disk/net drivers.
  # * evdev input passthrough w/ hotkey (both Ctrls by default): qemu
  #   input-linux entries in the XML; add the /dev/input/by-id paths to
  #   cgroup_device_acl above when wiring it.
  # * Error 43: only if it actually appears (unlikely on current NVIDIA
  #   drivers) — vendor_id spoof + kvm hidden in the XML.
  # * Looking Glass host app inside Windows: install B7 to match the host
  #   client/kvmfr (both B7 from nixpkgs).
  # * HDMI dummy plug on the 3080, rated for 2560x1440@240 (see plan).
}
