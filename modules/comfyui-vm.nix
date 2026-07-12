# Host-side plumbing for the ComfyUI sandbox VM (guest config lives in
# comfyui-guest.nix, runner in flake.nix packages.comfyui-vm). Unlike win11,
# that VM is plain QEMU run as z — no libvirt — so z needs direct access to
# the vfio group device and enough memlock to pin guest RAM (VFIO pins ALL
# of it for DMA; the default 8 MiB limit is hopeless).
{ pkgs, ... }:

{
  # The 3080's vfio group node (/dev/vfio/17 today; the runner derives the
  # number from sysfs) is root:root 0600 by default. Hand it to z at device
  # creation. Doesn't disturb win11: libvirt chowns the node to the VM user
  # on start regardless — and that user is z anyway (qemu.conf user="z",
  # modules/vfio.nix).
  services.udev.extraRules = ''
    SUBSYSTEM=="vfio", OWNER="z"
  '';

  # …but udev rules only run on device EVENTS, and the group node is created
  # once at boot: a switch reloads rules without replaying events, so on the
  # boot where this module first lands the node stays root-owned no matter
  # how often you switch (bitten by this for real). Activation runs as root
  # at boot AND on every switch — chown directly so switches converge.
  # Harmless no-ops when the node doesn't exist yet or win11 has it (same
  # owner either way).
  system.activationScripts.vfio-owner = ''
    chown z /dev/vfio/* 2>/dev/null || true
  '';

  # On win11 release libvirt restores the node's ownership to what it
  # recorded at VM start (xattr-based DAC remembering) — which is z whenever
  # boot-time ownership was right, so this hook is normally redundant. It's
  # the backstop for the one bad case: win11 started while the node was
  # root-owned, whose "original owner" libvirt then faithfully restores.
  # Hooks run as root; merges with the `isolate` hook in vfio.nix (each
  # becomes its own script under qemu.d/). NB: libvirtd-config.service is
  # what symlinks hooks into /var/lib/libvirt/hooks/qemu.d — it's an
  # inactive oneshot a switch does NOT re-run, so a new/changed hook takes
  # effect at next boot (or `systemctl restart libvirtd-config libvirtd`).
  virtualisation.libvirtd.hooks.qemu.vfio-owner = pkgs.writeShellScript "qemu-hook-vfio-owner" ''
    [ "$1" = "win11" ] && [ "$2" = "release" ] || exit 0
    chown z /dev/vfio/* 2>/dev/null || true
  '';

  # Memlock for z: qemu (as z) must mlock guest-RAM-sized memory for VFIO
  # DMA. Two mechanisms because sessions come in two flavors:
  #
  # pam_limits covers direct PAM sessions (TTY, ssh)…
  security.pam.loginLimits = [
    {
      domain = "z";
      item = "memlock";
      type = "-"; # soft + hard
      value = "unlimited";
    }
  ];
  # …but anything launched inside the graphical session (kitty etc.) lives
  # under user@1000.service, whose hard LimitMEMLOCK is systemd's 8 MiB
  # default — pam_limits never sees those processes, and an 8 MiB hard cap
  # can't be raised from inside. Drop-in (not a full unit override: user@ is
  # an upstream template) lifts it for the user manager; children inherit.
  # Takes effect once user@1000 restarts, i.e. after a FULL logout or reboot.
  systemd.services."user@" = {
    overrideStrategy = "asDropin";
    serviceConfig.LimitMEMLOCK = "infinity";
  };

  # The VM's single persistent artifact — data.img with venv + models — lives
  # on the big storage drive, not the NVMe root.
  systemd.tmpfiles.rules = [ "d /storage/comfyui-vm 0755 z users -" ];
}
