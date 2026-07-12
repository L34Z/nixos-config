# Hybrid 3080: nvidia driver on the host for native gaming, handed to a VM on
# demand — no reboot to switch. Steam/games render on the 3080 via PRIME
# offload while the desktop stays on the iGPU; the gpu-to-vfio / gpu-to-host
# oneshots below flip the card between the nvidia driver and vfio-pci. Both
# 3080 consumers go through them: the win11 libvirt hook (this file) and the
# comfyui-vm runner (flake.nix, plain qemu — no libvirt).
# Replaces the static vfio-pci.ids= boot binding of the GPU function; the
# card's AUDIO function stays statically vfio-bound (modules/vfio.nix) because
# the host never uses it and pipewire would otherwise adopt/hold it.
#
# PCI layout (captured 2026-07-12 from sysfs):
#   00:02.0  iGPU (i915)          — drives the desktop; niri renders on it
#   01:00.0  RTX 3080 / GA102     — offload render target ⇄ VM GPU
#   01:00.1  3080 HDA audio      — always vfio-pci
{ config, lib, pkgs, ... }:

let
  gpu = "0000:01:00.0";
  aud = "0000:01:00.1";

  # `drv <bdf>` -> current driver name, empty if unbound.
  drvFn = ''
    drv() { d=$(readlink "/sys/bus/pci/devices/$1/driver" 2>/dev/null) || return 0; basename "$d"; }
  '';

  # Audio invariant, enforced by BOTH scripts: 01:00.1 on vfio-pci, always.
  # Normally the boot-time ids= binding (vfio.nix) already did it; this
  # converges the one divergent case — libvirt reattaching the function to
  # snd_hda_intel on win11 release (managed='yes' hostdev).
  audioToVfio = ''
    if [ "$(drv ${aud})" != vfio-pci ]; then
      echo vfio-pci > /sys/bus/pci/devices/${aud}/driver_override
      [ -e /sys/bus/pci/devices/${aud}/driver ] && echo ${aud} > /sys/bus/pci/devices/${aud}/driver/unbind
      echo ${aud} > /sys/bus/pci/drivers_probe
    fi
  '';

  gpuToVfio = pkgs.writeShellScript "gpu-to-vfio" ''
    ${drvFn}
    ${audioToVfio}
    [ "$(drv ${gpu})" = vfio-pci ] && exit 0

    # Not enabled on this host, but if it ever is, it holds /dev/nvidia*:
    ${pkgs.systemd}/bin/systemctl stop nvidia-persistenced.service 2>/dev/null || true
    # Removal order matters: leaves depend on nvidia, so nvidia goes last.
    if ! ${pkgs.kmod}/bin/modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia; then
      echo "cannot unload nvidia — something on the host is using the 3080:" >&2
      ${pkgs.psmisc}/bin/fuser -v /dev/nvidia* /dev/dri/by-path/pci-${gpu}-* >&2 || true
      echo "close it (or check what nvidia-smi lists) and retry" >&2
      exit 1
    fi
    ${pkgs.kmod}/bin/modprobe vfio-pci
    echo vfio-pci > /sys/bus/pci/devices/${gpu}/driver_override
    echo ${gpu} > /sys/bus/pci/drivers_probe
    [ "$(drv ${gpu})" = vfio-pci ] # loud failure if the bind didn't take
  '';

  gpuToHost = pkgs.writeShellScript "gpu-to-host" ''
    ${drvFn}
    echo "" > /sys/bus/pci/devices/${gpu}/driver_override
    if [ "$(drv ${gpu})" = vfio-pci ]; then
      echo ${gpu} > /sys/bus/pci/drivers/vfio-pci/unbind
    fi
    # -a: several modules (without it the extra names would be parsed as
    # module PARAMETERS for nvidia)
    ${pkgs.kmod}/bin/modprobe -a nvidia nvidia_modeset nvidia_uvm nvidia_drm
    [ -e /sys/bus/pci/devices/${gpu}/driver ] || echo ${gpu} > /sys/bus/pci/drivers_probe
    ${audioToVfio}
    [ "$(drv ${gpu})" = nvidia ]
  '';
in
{
  # ── nvidia driver (open kernel modules — GA102 is fully supported) ──────
  services.xserver.videoDrivers = [ "nvidia" ]; # installs + loads the driver; no X runs
  hardware.nvidia = {
    open = true;
    # nvidia-drm.modeset=1: required for PRIME offload (dma-buf export of the
    # rendered frames back to the iGPU for scanout).
    modesetting.enable = true;
    # Render OFFLOAD, not sync: the desktop must never depend on the 3080 or
    # it could not be unbound while logged in. Run a game on the card with
    # `nvidia-offload <cmd>` — see modules/steam.nix for the Steam recipe.
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # the `nvidia-offload` wrapper script
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
    # Runtime PM (finegrained) deliberately off: it adds udev/rebind machinery
    # that fights the unload cycle below, and with fbdev off + no host output
    # on the card the idle draw is already modest. Revisit if it bothers.
    powerManagement.enable = false;
    powerManagement.finegrained = false;
  };

  # ── Keep the host OFF the 3080 so it can always be unloaded ─────────────
  # The card keeps a live DP cable to the G7's 2nd input (Looking Glass needs
  # the head/EDID — docs/win11-vm.md). Two host-side things would otherwise
  # grab it through that and make `modprobe -r nvidia*` fail at VM start:
  #
  # 1. niri opens every DRM card on its seat, cable or not. Assigning the card
  #    to a different logind seat hides it — smithay's udev backend filters on
  #    ID_SEAT (default seat0). PRIME offload is unaffected: it goes through
  #    the render node (/dev/dri/renderD*), which is not seat-tagged.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x10de", ENV{ID_SEAT}="seat-vfio"
  '';
  # 2. fbcon: nvidia-drm's fbdev emulation would register a framebuffer
  #    console on that head and pin nvidia_drm (the classic single-GPU-
  #    passthrough vtconsole dance). fbdev=0 keeps modeset without the fb.
  #    mkForce because the nixpkgs nvidia module sets fbdev=1 whenever
  #    offload/modesetting is on (it ends up in modprobe.d/nixos.conf).
  hardware.nvidia.moduleParams."nvidia-drm".fbdev = lib.mkForce 0;

  # ── The mode switch, as root-owned oneshots ──────────────────────────────
  # RemainAfterExit stays false so every `systemctl start` re-runs the script
  # (they're idempotent). Failure output lands in the journal; callers dump it.
  systemd.services.gpu-to-vfio = {
    description = "Detach the 3080 from the host (nvidia -> vfio-pci)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gpuToVfio}";
    };
  };
  systemd.services.gpu-to-host = {
    description = "Return the 3080 to the host (vfio-pci -> nvidia)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gpuToHost}";
    };
  };
  # The comfyui-vm runner (runs as z, no libvirt) starts these itself;
  # scope the passwordless grant to exactly these two units.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "z" &&
          action.lookup("verb") == "start" &&
          (action.lookup("unit") == "gpu-to-vfio.service" ||
           action.lookup("unit") == "gpu-to-host.service")) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── Hand the 3080 to win11 / take it back ───────────────────────────────
  # prepare fires before libvirt touches the hostdevs; with the card already
  # on vfio-pci, its managed='yes' detach is a no-op. A failing prepare aborts
  # the VM start — the journal dump surfaces WHY in the virsh/virt-manager
  # error (likely: a game still running, or a chromium/electron app that
  # enumerated the GPU and kept the fd).
  virtualisation.libvirtd.hooks.qemu.gpu-rebind = pkgs.writeShellScript "qemu-hook-gpu-rebind" ''
    [ "$1" = "win11" ] || exit 0
    case "$2" in
      prepare)
        if ! systemctl start gpu-to-vfio.service; then
          echo "win11: could not detach the 3080 from the host:" >&2
          journalctl -u gpu-to-vfio.service -n 15 --no-pager >&2 || true
          exit 1
        fi
        ;;
      release)
        systemctl start gpu-to-host.service || true
        ;;
    esac
  '';
}
