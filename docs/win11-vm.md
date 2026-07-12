# win11 VM — install & post-install

Artifacts live in `/home/z/vms/win11/` (domain XML, autounattend, ISOs, 512G
raw image). The domain is defined on `qemu:///system` — **always** use
`virsh -c qemu:///system`; the session daemon shows nothing.

## Prerequisite

Just switch — the qemu.conf now applies itself:

```
sudo nixos-rebuild switch --flake ~/nixos#nix
```

Stock NixOS pins `libvirtd` `restartIfChanged = false` and never re-runs the
oneshot `libvirtd-config` on switch, so `qemu.conf` edits (device ACL,
`namespaces = []`) used to sit in the store and stay **stale in
`/var/lib/libvirt/qemu.conf` until a reboot or manual `systemctl restart
libvirtd`**. That bit us once: the VM started under the old namespace config, so
its ivshmem shm landed in a private `/dev/shm` the host LG client couldn't see
(`win11` reported `/dev/shm/looking-glass never appeared`). `modules/vfio.nix`
now ties both units to the `qemu.conf` content (`restartTriggers` +
`restartIfChanged = mkForce true`), so a plain `switch` regenerates the file and
reconnects the daemon. A libvirtd restart does **not** kill running domains
(qemu runs in its own scope; libvirtd reconnects); they adopt the new config on
their next start. Manual fallback if ever needed:
`sudo systemctl restart libvirtd-config.service libvirtd.service`.

There is a second way to hit the same `never appeared` error: logind's default
`RemoveIPC=yes` deletes all of a user's POSIX shm when their last session ends,
and qemu runs as z — so a desktop crash/logout unlinks `/dev/shm/looking-glass`
under the **running** VM (bit us 2026-07-03 when Hyprland segfaulted). Only a VM
power-cycle recreates the file (a guest reboot isn't enough if Windows ignores
the ACPI shutdown — check `virsh -c qemu:///system domstate win11`, then
`virsh -c qemu:///system destroy win11` and start again). `modules/vfio.nix`
now sets `RemoveIPC=no` so logind leaves the shm alone.

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
3. **MSI mode — done 2026-07-03.** The GPU (`DEV_2216`) already had
   `MSISupported=1`; the *High Definition Audio Controller* (`DEV_1AEF`) was
   `0` (line-based) and is now set to `1`. Applies on the next guest reboot.
   **Re-check after every GeForce driver update** — the installer likes to flip
   the audio function back to line-based.

   No RDP/Device-Manager needed: `qemu-ga` runs as SYSTEM, so drive the guest
   registry from the host while the VM is up. Report, then set:
   ```
   # PowerShell body, over VEN_10DE PCI devices:
   #   report: (Get-ItemProperty $imp -Name MSISupported).MSISupported
   #   set:    Set-ItemProperty $imp -Name MSISupported -Value 1 -Type DWord
   # where $imp = <inst>\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties
   # base64 it (UTF-16LE) and run via:
   virsh -c qemu:///system qemu-agent-command win11 \
     '{"execute":"guest-exec","arguments":{"path":"powershell.exe",
       "arg":["-NoProfile","-EncodedCommand","<b64>"],"capture-output":true}}'
   # then guest-exec-status {"pid":N} and base64 -d the out-data.
   ```
4. **Display head for the 3080 — done (DisplayPort → G7).** A DP cable from a
   3080 output to the Samsung G7's second DP input gives a true 2560x1440@240
   EDID; the G7 need not have that input selected (the GPU only needs the head
   present). LG captures it at 2560x1440, confirmed. HDMI can't do 1440p240
   (HDMI 2.0 ≈ 14 Gbps < ~23 needed; the G7's 240 Hz is DP-only) so any dummy
   plug must be DP/HDMI 2.1. **Caveat still live:** if the G7 drops EDID on the
   unselected input the head can churn and LG loses capture (cf. the Dell HDMI
   churn hit host-side).
5. **Looking Glass B7 host + IVSHMEM driver — done.** Host app B7 (matches the
   nixpkgs client) installed in-guest as an auto-starting service; the
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

## Launching

The `win11` fish function (`home/dotfiles/fish/aliases.fish`, live-symlinked —
no rebuild) is the one command:

- `win11` — start the domain if it isn't running, then open the Looking Glass
  window (backgrounded/disowned; LG reads `~/.config/looking-glass/client.ini`).
  Press **KEY_END** to toggle capture (grabs kbd+mouse, relative); hold it for
  the help menu.
- `win11 stop` — graceful ACPI shutdown · `win11 kill` — force off ·
  `win11 status` — domain state.

Display is the 3080→G7 head (sole output; `<video model='none'/>`). Do **not**
run `virt-viewer` alongside LG — they fight over the one Spice server.

## Notes

- Secure Boot: firmware is SB-*capable* but no keys enrolled (QEMU's edk2
  ships no MS-vars template). Win11 installs fine. Enroll keys in-guest only
  if some anticheat (Vanguard etc.) demands SB *enabled*.
- While the VM runs, the host is confined to the E-cores (16–19) by the
  libvirt hook in `modules/vfio.nix`; it resets on VM shutdown.
- Consciously skipped: hugepages (would reserve 24 of 31 GiB even with the
  VM off). Revisit with 1G pages if chasing the last few percent.

## Host/VM GPU sharing (2026-07-12)

The 3080's GPU function is no longer statically bound to vfio-pci. At boot
the host's nvidia driver owns it (`modules/nvidia-hybrid.nix`) so Steam can
render on it via PRIME offload (`gamemoderun nvidia-offload %command%`); the
desktop itself stays on the iGPU. The card's AUDIO function (`01:00.1`,
`10de:1aef`) stays statically vfio-bound — the host never uses it and
pipewire would otherwise hold it open.

Two root-owned oneshots do the switching (`nvidia-hybrid.nix`; z may start
them passwordless via a scoped polkit rule):

- `gpu-to-vfio.service` — unloads `nvidia_uvm/nvidia_drm/nvidia_modeset/
  nvidia`, binds `01:00.0` to vfio-pci via `driver_override`. Fails loudly if
  something on the host still holds the card (`fuser` dump in the journal) —
  usually a game still running, or a chromium/electron app that enumerated
  the GPU. Close it, retry.
- `gpu-to-host.service` — the reverse. Both also re-assert the audio-on-vfio
  invariant (libvirt's managed reattach can bounce it to snd_hda_intel).

Both 3080 consumers go through them automatically:
- **win11**: the `gpu-rebind` libvirt hook calls gpu-to-vfio on prepare
  (a failure aborts the VM start with the journal in the error) and
  gpu-to-host on release.
- **comfyui-vm**: the runner (flake.nix) detaches on start and returns the
  card via its exit trap.

Native gaming and either VM are mutually exclusive at runtime, by definition.

Guardrails that make the nvidia unload reliable (both in `nvidia-hybrid.nix`):
- udev assigns the 3080's DRM card to seat `seat-vfio`, so niri (seat0) never
  opens it despite the live DP cable to the G7's 2nd input. Offload still
  works — it uses the render node, which isn't seat-tagged.
- `nvidia-drm` loads with `fbdev=0` (modprobe.d, mkForce over the nixpkgs
  default) so no framebuffer console can pin `nvidia_drm`.
