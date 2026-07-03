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
      # Glass) without per-device permission fights. The device ACL is the
      # qemu default plus kvmfr0.
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
          "/dev/rtc", "/dev/hpet",
          "/dev/kvmfr0"
        ]
      '';
    };
  };
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
  #   client/kvmfr (both B7 from nixpkgs). IVSHMEM driver needs a manual
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
