# win11 VM — install & post-install

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

## Install — done 2026-07-03 (manual DISM; the unattended path failed)

**The autounattend / new graphical Setup path does not work on 25H2.**
Booting the ISO into the redesigned "Windows 11 Setup" dies with
`0xD000A000 - 0x40031`. The root cause is NOT a setup/media bug: WinPE ships
no virtio-blk driver, so the `vda` disk is invisible (`diskpart` → "There are
no fixed disks to show") and the autounattend's WillWipeDisk has no target.
`setup.exe /installfrom:<wim>` does **not** force the legacy setup on 25H2
either. Don't chase `0xD000A000` as a media problem — it's the missing storage
driver.

What worked was deploying the image by hand from a WinPE prompt (boot the ISO,
then **Shift+F10**), which bypasses Setup entirely:

```
rem 1. load virtio storage so the disk appears (from virtio-win.iso; the CD
rem    letter varies — it's the one with a \viostor folder, here E:)
drvload E:\viostor\w11\amd64\viostor.inf

rem 2. partition (UEFI/GPT)
diskpart
  rescan
  list disk                       rem the 512G disk now shows as disk 0
  select disk 0
  clean
  convert gpt
  create partition efi size=260
  format quick fs=fat32 label=System
  assign letter=S
  create partition msr size=16
  create partition primary
  format quick fs=ntfs label=Windows
  assign letter=W
  exit

rem 3. apply image (D: = win11.iso; get the Pro index from Get-ImageInfo)
dism /Get-ImageInfo /ImageFile:D:\sources\install.wim
dism /Apply-Image /ImageFile:D:\sources\install.wim /Index:6 /ApplyDir:W:\

rem 4. ESSENTIAL — inject viostor into the applied image, else first boot
rem    bugchecks 0x7B INACCESSIBLE_BOOT_DEVICE
dism /Image:W:\ /Add-Driver /Driver:E:\viostor\w11\amd64\viostor.inf

rem 5. bootloader
bcdboot W:\Windows /s S: /f UEFI
```

Then reboot into OOBE from the host:

```
virsh -c qemu:///system change-media win11 sda --eject --live --config  # win11.iso
virsh -c qemu:///system change-media win11 sdc --eject --live --config  # unattend.iso
virsh -c qemu:///system reset win11    # WinPE ignores ACPI `virsh reboot`
```

Leave `sdb` (virtio-win.iso) mounted for guest tools. Ejecting media only
drops the virt-viewer/Spice *client* — the VM keeps running; reconnect with:

```
virt-viewer -c qemu:///system --wait win11 &
```

At OOBE's "Let's connect you to a network", for a **local account**:
**Shift+F10** → `start ms-cxh:localonly` → Enter. (`oobe\bypassnro` was removed
in 24H2+; having no NIC makes this path smoother.)

Display during install/OOBE is Spice at `localhost:5900` (fixed port).
Input: NuPhy kbd + Razer dongle mouse via evdev — **both Ctrls** (`ctrl-ctrl`;
`grab='all'` releases keyboard+mouse together) toggles between host and guest.
It is **not** Shift+F12.

## Post-install (in the guest, over Spice)

1. **NVIDIA driver — done.** GeForce driver installed clean; the 3080
   enumerates with **no Error 43** (hyperv enlightenments; no vendor_id spoof
   or kvm-hidden needed on current drivers). `nvidia-smi` lists the card →
   passthrough verified end-to-end.
2. **virtio guest tools — done.** `virtio-win-guest-tools.exe` from the mounted
   virtio-win.iso (NetKVM/balloon/serial/qemu-ga); networking works.
3. **MSI check (pending).** Device Manager → the 3080's *High Definition Audio
   Controller* → Resources. Negative IRQ = MSI, fine. Positive IRQ =
   line-based: set `MSISupported` (DWORD) = 1 under
   `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_10DE&DEV_1AEF&...\<instance>\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`
   and reboot the guest. **Re-check after every GeForce driver update** — the
   installer likes to flip it back.
4. **Display head for the 3080 (pending — blocks Looking Glass).** NVIDIA
   Control Panel has no display options and there's no correct resolution/
   refresh until the card drives an active output; right now it's headless (the
   Spice/QXL virtual display you see is a throwaway console, ~60 Hz — don't
   bother tuning it). Options, best first:
   - **Real monitor (preferred):** run **DisplayPort** from a 3080 DP output to
     the Samsung G7's second DP input → a true 2560x1440@240 EDID. You don't
     have to select that input (the GPU only needs the head present), and you
     gain a native-input gaming path (switch the monitor source) alongside LG.
     HDMI can't do 1440p240 (HDMI 2.0 ≈ 14 Gbps data < ~23 needed); the G7's
     240 Hz is DP-only. **Caveat:** if the G7 drops EDID/hotplug on the
     unselected input, the head churns and LG loses capture (cf. the Dell HDMI
     churn hit host-side) — verify the guest keeps the head while the monitor
     shows the host input.
   - **Dummy plug:** hardware-clean, but must be **DP or HDMI 2.1** for 240 Hz,
     and its EDID must advertise 1440p240 (cheap HDMI-2.0 4K@60 plugs won't).
   - **Virtual display driver (VDD, software stopgap):** an IddCx virtual
     monitor (e.g. MikeTheTech's VDD) lets you build/test LG now with no
     hardware. Doesn't reduce GPU render FPS, but adds ~1 frame of composition
     latency and may forfeit fullscreen-exclusive flip vs a real head — fine as
     a bridge; set it to 1440p240 so swapping to the real head changes nothing.
5. **Looking Glass B7 host app (pending).** Install B7 to match the host
   client/kvmfr (both B7 from nixpkgs). The **IVSHMEM driver still needs a
   manual install** — the by-hand DISM deploy bypassed the autounattend
   injection (not urgent: LG can't capture until step 4 gives it a head). The
   shared memory is a plain shm file (`/dev/shm/looking-glass`, the LG client's
   default) — **not kvmfr**: on kernel 6.18 VFIO can't DMA-map kvmfr device
   memory and qemu aborts the moment OVMF programs the ivshmem BAR (hw_error in
   vfio_container_region_add, SIGABRT ~5 s into boot). Retry kvmfr when the
   module catches up with the kernel.

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
