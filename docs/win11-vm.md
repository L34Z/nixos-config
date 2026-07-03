# win11 VM — first boot & post-install

Artifacts live in `/home/z/vms/win11/` (domain XML, autounattend, ISOs, 512G
raw image). The domain is defined on `qemu:///system` — **always** use
`virsh -c qemu:///system`; the session daemon shows nothing.

## Prerequisite (once)

The running generation must include the latest `modules/vfio.nix`
(evdev ACL, `namespaces = []`, host-isolation hook):

```
sudo nixos-rebuild switch --flake ~/nixos#nix
sudo systemctl restart libvirtd   # only if no VM is running
```

NixOS deliberately does **not** restart libvirtd on switch (it would kill
running VMs), so qemu.conf changes (device ACL, namespaces) and hook
updates from `modules/vfio.nix` are NOT live until libvirtd restarts.

## First boot

```
virt-viewer -c qemu:///system --wait win11 &
virsh -c qemu:///system start win11
```

1. In the viewer, press a key at **"Press any key to boot from CD or DVD"**
   (it times out after ~5 s; if missed, `virsh reset win11` and try again).
2. Then take your hands off the keyboard. Setup runs fully unattended:
   wipes the virtio disk, installs Win11 Pro 25H2, drivers (viostor, NetKVM,
   ivshmem) staged from the CDs, local admin `z` with autologon, virtio
   guest tools + high-performance power plan on first logon.
3. **When setup reboots the first time** (after "copying files", ~5 min), run:

   ```
   virsh -c qemu:///system change-media win11 sda --eject --live --config
   ```

   The install media isn't needed after phase 1, and a stray keypress at the
   CD prompt on a later reboot would silently **re-wipe the disk**
   (WillWipeDisk=true, all confirmations suppressed).

Display during install is Spice at `localhost:5900` (fixed port).
Input: the NuPhy kbd + Razer dongle mouse pass through via evdev —
**both Ctrls toggles** keyboard between host and guest.

## Post-install (in the guest, over Spice)

1. Install the NVIDIA GeForce driver (3080 shows up once the driver loads).
2. MSI check: Device Manager → the 3080's *High Definition Audio Controller*
   → Resources. Negative IRQ = MSI, fine. Positive IRQ = line-based: set
   `MSISupported` (DWORD) = 1 under
   `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_10DE&DEV_1AEF&...\<instance>\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`
   and reboot the guest. **Re-check after every GeForce driver update** —
   the installer likes to flip it back.
3. Install the Looking Glass **B7** host app (must match the host client,
   both B7 from nixpkgs). The IVSHMEM driver is already bound (staged from
   unattend.iso — the stable virtio-win ISO doesn't ship it).
   The shared memory is a plain shm file (`/dev/shm/looking-glass`, the LG
   client's default) — **not kvmfr**: on kernel 6.18 VFIO can't DMA-map
   kvmfr device memory and qemu aborts the moment OVMF programs the ivshmem
   BAR (hw_error in vfio_container_region_add, SIGABRT ~5 s into boot).
   Retry kvmfr when the module catches up with the kernel.
4. LG capture needs an active output on the 3080: nothing to capture until
   the **HDMI dummy plug** (2560x1440@240-capable) arrives. Spice remains the
   display until then.

## Once Looking Glass works

In `virsh edit win11` (or edit `/home/z/vms/win11/win11.xml` and redefine):

- `<video><model type='none'/></video>`, drop the usb tablet input.
- **Keep** `<graphics type='spice'>`, `<sound>`, `<audio>` and the channels —
  Spice carries LG's audio and clipboard.
- Detach all three cdroms; move `<boot order='1'/>` to the vda disk.

## Notes

- Secure Boot: firmware is SB-*capable* but no keys enrolled (QEMU's edk2
  ships no MS-vars template). Win11 installs fine. Enroll keys in-guest only
  if some anticheat (Vanguard etc.) demands SB *enabled*.
- While the VM runs, the host is confined to the E-cores (16–19) by the
  libvirt hook in `modules/vfio.nix`; it resets on VM shutdown.
- Consciously skipped: hugepages (would reserve 24 of 31 GiB even with the
  VM off). Revisit with 1G pages if chasing the last few percent.
