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
4. **Display head for the 3080 — done (DisplayPort → G7).** A DP cable from a
   3080 output to the Samsung G7's second DP input gives a true 2560x1440@240
   EDID; the G7 need not have that input selected (the GPU only needs the head
   present). LG captures it at 2560x1440, confirmed. HDMI can't do 1440p240
   (HDMI 2.0 ≈ 14 Gbps < ~23 needed; the G7's 240 Hz is DP-only) so any dummy
   plug must be DP/HDMI 2.1. **Caveat still live:** if the G7 drops EDID on the
   unselected input the head can churn and LG loses capture (cf. the Dell HDMI
   churn hit host-side).
5. **Looking Glass B7 host + IVSHMEM driver — done.** Host app B7 (matches the
   nixpkgs client/kvmfr) installed in-guest as an auto-starting service; the
   **IVSHMEM driver** was installed by hand from `unattend.iso` →
   `\drivers\ivshmem\ivshmem.inf` (Device Manager → *PCI standard RAM
   Controller*), since the DISM deploy bypassed the autounattend injection.
   Shared memory is a plain shm file (`/dev/shm/looking-glass`, the LG client's
   default) — **not kvmfr**: on kernel 6.18 VFIO can't DMA-map kvmfr device
   memory and qemu aborts the moment OVMF programs the ivshmem BAR (hw_error in
   vfio_container_region_add, SIGABRT ~5 s into boot). Retry kvmfr when the
   module catches up with the kernel.
6. **Input capture — Looking Glass, not evdev.** evdev `<input type='evdev'>`
   passthrough was tried and **abandoned** (see `modules/vfio.nix`): input-linux
   opens the NuPhy/Razer nodes but QEMU silently closes each fd on the first
   event read, so the grab never holds (and it read every host keystroke). Use
   LG's own capture instead — `~/.config/looking-glass/client.ini`:
   `escapeKey=KEY_END` (the Air75 V2 has no ScrollLock) toggles capture,
   `rawMouse=yes` for relative gaming input. Spice still carries clipboard/audio.

## Cleanup once Looking Glass works

Edit the domain (`virsh edit win11`, or edit `/home/z/vms/win11/win11.xml` and
redefine) — **keep** `<graphics type='spice'>`, `<sound>`, `<audio>` and the
channels (Spice carries LG's clipboard/audio):

- **`<video><model type='none'/></video>` — done 2026-07-03.** This is not just
  tidy, it's *required*: with both QXL and the 3080 present, every Spice
  connect/disconnect hot-plugs the QXL display, reshuffling the primary and
  resolution, which crashed the LG host capture and warped the absolute mouse
  (clicks jumped to a fixed point). Also **never run virt-viewer alongside the
  LG client** — they fight over the one Spice server and virt-viewer kicks LG
  off. With `model='none'` the 3080/G7 is the sole display: mouse aligns, no
  flapping, and there's no QXL picture to tempt you into virt-viewer.
- **Cdroms detached + `<boot order='1'/>` on vda — done 2026-07-03** (applies
  next boot). **Kept the usb tablet** on purpose: it's the *absolute* pointer,
  so the LG mouse tracks the window without capturing — needed for FL Studio /
  desktop use. The earlier click-jump was the dual-display bug, not the tablet;
  `model='none'` fixed it. (Fallback if LG ever won't start: no Spice picture
  anymore — SSH → `virsh destroy win11`, or revert `model='none'` for a QXL
  console.)

## Notes

- Secure Boot: firmware is SB-*capable* but no keys enrolled (QEMU's edk2
  ships no MS-vars template). Win11 installs fine. Enroll keys in-guest only
  if some anticheat (Vanguard etc.) demands SB *enabled*.
- While the VM runs, the host is confined to the E-cores (16–19) by the
  libvirt hook in `modules/vfio.nix`; it resets on VM shutdown.
- Consciously skipped: hugepages (would reserve 24 of 31 GiB even with the
  VM off). Revisit with 1G pages if chasing the last few percent.
