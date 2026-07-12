{
  description = "z's NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Quickshell-based desktop shell (bar/launcher/notifs/OSD).
    # Upstream builds against unstable; if quickshell ever fails to build on
    # the 26.05 channel, drop this `follows` and eat the extra store closure.
    caelestia-shell.url = "github:caelestia-dots/shell";
    caelestia-shell.inputs.nixpkgs.follows = "nixpkgs";

    # DankMaterialShell — quickshell-based shell for the niri session.
    # Same caveat as caelestia: upstream tracks unstable; if it ever fails to
    # build on the 26.05 channel, drop this `follows`.
    dms.url = "github:AvengeMedia/DankMaterialShell";
    dms.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, disko, home-manager, ... }: {
    nixosConfigurations.nix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        ./hosts/nix/configuration.nix
      ];
    };

    # ── Disposable VM (Qubes-style dispvm) ──────────────────────────────
    # Guest config for an amnesic one-shot Firefox session; the design and
    # the no-persistence guarantees are documented in the module itself.
    nixosConfigurations.disp = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./modules/dispvm-guest.nix ];
    };

    # ── ComfyUI sandbox VM ──────────────────────────────────────────────
    # Untrusted-model image generation on the passed-through 3080; tmpfs
    # root, one persistent data disk. Guest config documents the
    # containment model; host plumbing is modules/comfyui-vm.nix.
    nixosConfigurations.comfyui = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./modules/comfyui-guest.nix ];
    };

    # `comfyui-vm` (on PATH via home/z.nix). Creates the data disk on first
    # run, attaches the GPU, refuses to race win11 for it. Env knobs:
    #   COMFYUI_VM_DATA=<path>   data disk location (default /storage/comfyui-vm/data.img)
    #   COMFYUI_VM_DISK=<size>   size at creation time (default 300G, sparse)
    #   COMFYUI_VM_NO_GPU=1      boot without the 3080 (smoke tests)
    #   COMFYUI_VM_NO_NET=1      no outbound net (slirp restrict=on; UI still works)
    packages.x86_64-linux.comfyui-vm =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in
      pkgs.writeShellApplication {
        name = "comfyui-vm";
        runtimeInputs = [
          pkgs.e2fsprogs
          pkgs.libvirt
        ];
        text = ''
          for a in "$@"; do
            if [ "$a" = -h ] || [ "$a" = --help ]; then
              cat <<'EOF'
          comfyui-vm — ComfyUI in a throwaway NixOS guest on the passed-through RTX 3080

          Usage: comfyui-vm [qemu args...]
            Any arguments are passed straight to qemu (e.g. -display none).

          Environment knobs:
            COMFYUI_VM_DATA=<path>   data disk (default /storage/comfyui-vm/data.img)
            COMFYUI_VM_DISK=<size>   size when the disk is first created (default 300G, sparse)
            COMFYUI_VM_NO_GPU=1      boot without the 3080 (smoke tests, CPU-only)
            COMFYUI_VM_NO_NET=1      cut outbound networking (slirp restrict=on);
                                     the UI forward keeps working
            QEMU_OPTS / QEMU_NET_OPTS are honored as usual (qemu-vm.nix).

          The VM:
            * UI at http://localhost:8188 on the host (loopback only).
            * Root fs is tmpfs; the ONLY persistent file is the data disk —
              venv, models, outputs. Delete it to decontaminate.
            * First boot git-clones ComfyUI + ComfyUI-INT8-Fast and pip-installs
              torch cu130 (several GB): watch `journalctl -fu comfyui` in the
              QEMU console (auto-logged-in root).
            * Models go in /data/ComfyUI/models/... — download in the console
              (aria2c -x8 <url>), then load your workflow in the UI.
            * Refuses to start while win11 is running: same GPU.
            * Detaches the 3080 from the host's nvidia driver on start and
              returns it on exit (gpu-to-vfio/gpu-to-host — nvidia-hybrid.nix).

          Config: modules/comfyui-guest.nix (guest), modules/comfyui-vm.nix (host),
          runner in flake.nix (packages.comfyui-vm).
          EOF
              exit 0
            fi
          done

          # The 3080 is single-owner: win11 (libvirt) and this VM share it.
          if virsh -c qemu:///system list --name 2>/dev/null | grep -qx win11; then
            echo "comfyui-vm: win11 is running and owns the 3080 — shut it down first." >&2
            exit 1
          fi

          # One trap for all cleanup: the scratch dir (created below) and —
          # when we detached it — returning the 3080 to the host's nvidia
          # driver on the way out.
          gpu_detached=0
          d=""
          cleanup() {
            cd /
            if [ -n "$d" ]; then rm -rf "$d"; fi
            if [ "$gpu_detached" = 1 ]; then
              systemctl start gpu-to-host.service || true
            fi
          }
          trap cleanup EXIT

          if [ "''${COMFYUI_VM_NO_GPU:-}" != 1 ]; then
            # Hybrid GPU (modules/nvidia-hybrid.nix): the 3080 belongs to the
            # host's nvidia driver until a VM claims it. Detach it — a
            # root-owned oneshot, passwordless for z via the polkit rule in
            # that module. Fails while something still renders on the card
            # (a game, an electron app that enumerated it); the journal
            # names the culprit.
            if ! systemctl start gpu-to-vfio.service; then
              echo "comfyui-vm: could not detach the 3080 from the host:" >&2
              journalctl -u gpu-to-vfio.service -n 10 --no-pager >&2 || true
              exit 1
            fi
            gpu_detached=1

            # Derive the vfio group from sysfs instead of hardcoding 17.
            group=$(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/iommu_group)")
            dev=/dev/vfio/$group
            # The node appears when the group binds vfio-pci (just happened)
            # and udev chowns it to z (comfyui-vm.nix rule) a beat later —
            # wait out the race instead of failing on it.
            for _ in $(seq 30); do
              if [ -w "$dev" ]; then break; fi
              sleep 0.1
            done
            if [ ! -w "$dev" ]; then
              echo "comfyui-vm: $dev never became z-writable — check the" >&2
              echo "  SUBSYSTEM==\"vfio\" udev rule (modules/comfyui-vm.nix): ls -l $dev" >&2
              exit 1
            fi
            # VFIO pins all guest RAM; fail early with a hint instead of a
            # cryptic qemu ENOMEM. 22 GiB covers the 20 GiB guest + overhead.
            ml=$(ulimit -l)
            if [ "$ml" != unlimited ] && [ "$ml" -lt $((22 * 1024 * 1024)) ]; then
              echo "comfyui-vm: memlock limit is $ml KiB — too low to pin guest RAM." >&2
              echo "  After 'nh os switch', reboot (or log out of EVERY session so" >&2
              echo "  user@1000.service restarts) to pick up the new limit." >&2
              exit 1
            fi
            QEMU_OPTS="''${QEMU_OPTS:-} -device vfio-pci,host=01:00.0"
          fi

          # Persistent disk: venv + models + outputs, and the ONLY host file
          # a malicious model could contaminate. Raw + sparse so mkfs works
          # from the host and unused space costs nothing.
          data=''${COMFYUI_VM_DATA:-/storage/comfyui-vm/data.img}
          if [ ! -f "$data" ]; then
            mkdir -p "$(dirname "$data")"
            truncate -s "''${COMFYUI_VM_DISK:-300G}" "$data"
            mkfs.ext4 -q -L comfy-data "$data"
            echo "comfyui-vm: created $data (''${COMFYUI_VM_DISK:-300G}, sparse)"
          fi
          QEMU_OPTS="''${QEMU_OPTS:-} -drive file=$data,if=virtio,format=raw,cache=none,aio=native,discard=unmap"
          export QEMU_OPTS

          # restrict=on cuts guest<->world (and guest->host-loopback via
          # 10.0.2.2); the hostfwd'd 8188 keeps working.
          if [ "''${COMFYUI_VM_NO_NET:-}" = 1 ]; then
            export QEMU_NET_OPTS="restrict=on''${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"
          fi

          # Same scratch hygiene as dispvm: qemu control sockets etc. on
          # tmpfs, gone with the VM. (Removed by the cleanup trap above.)
          d=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}" comfyui-vm.XXXXXX)
          export TMPDIR="$d"
          cd "$d"
          echo "comfyui-vm: UI will be at http://localhost:8188 (first boot installs for a while)"
          ${self.nixosConfigurations.comfyui.config.system.build.vm}/bin/run-comfyui-vm "$@"
        '';
      };

    # `nix run ~/nixos#dispvm` — also on PATH and in the app launcher via
    # home/z.nix. Wraps the qemu runner so its scratch files (control
    # sockets, xchg share) land on tmpfs and vanish with the VM.
    packages.x86_64-linux.dispvm =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in
      pkgs.writeShellApplication {
        name = "dispvm";
        text = ''
          # Default qemu flags, overridable wholesale by setting QEMU_OPTS:
          #  - GL display: required by the guest's virtio-vga-gl (headless
          #    runs: QEMU_OPTS="-display egl-headless ..." — not "none").
          #  - Audio only when the host has a PipeWire socket, so the VM
          #    still boots from a bare TTY. The stream is a normal client:
          #    route it to the Fireface once and wireplumber remembers;
          #    with the Fireface gone it just follows the default sink.
          if [ -z "''${QEMU_OPTS:-}" ]; then
            # zoom-to-fit: scale the framebuffer into however the compositor
            # tiles the window (e.g. next to the bar); on top of that, cage
            # follows window resizes with a real guest mode change, so once
            # the window settles the image is 1:1 again.
            QEMU_OPTS="-display gtk,gl=on,zoom-to-fit=on"
            if [ -S "''${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0" ]; then
              QEMU_OPTS="$QEMU_OPTS -audiodev pipewire,id=snd0 -device virtio-sound-pci,audiodev=snd0"
            fi
          fi
          export QEMU_OPTS
          d=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}" dispvm.XXXXXX)
          trap 'cd /; rm -rf "$d"' EXIT
          export TMPDIR="$d"
          cd "$d"
          ${self.nixosConfigurations.disp.config.system.build.vm}/bin/run-disp-vm "$@"
        '';
      };
  };
}
