# ComfyUI sandbox VM: image generation with UNTRUSTED models (Krea2 etc.),
# fully contained in a QEMU guest. `comfyui-vm` boots this config with the
# RTX 3080 passed through (the card is already vfio-bound for win11 — see
# modules/vfio.nix — so the two VMs share it and must never run at once;
# the runner refuses to start while win11 is up).
#
# Containment model (why a malicious model can't touch the host):
#   * / is tmpfs — no root disk image exists; qemu-vm.nix overlays a tmpfs
#     over the host store, which is shared READ-ONLY over 9p (same trick as
#     dispvm-guest.nix). Everything a compromised guest can persist lives in
#     exactly ONE host file: the raw data disk the runner attaches
#     (/storage/comfyui-vm/data.img by default) — delete it, contamination gone.
#   * ComfyUI itself, its venv, and all pip filth also live on that disk, so
#     the host never runs pip / arbitrary setup.py code either.
#   * Residual risks, for honesty's sake: qemu escapes; GPU firmware attacks
#     via the passed-through 3080; and slirp networking maps 10.0.2.2 to the
#     host loopback, so a hostile guest can reach host services that bind
#     127.0.0.1. Don't run secrets-bearing localhost services while chasing
#     sketchy checkpoints, or start with COMFYUI_VM_NO_NET=1 (runner env).
#
# This is a GUEST NixOS config, built standalone via flake.nix
# (nixosConfigurations.comfyui + packages.comfyui-vm). The host never
# imports it. Host-side plumbing (vfio perms, memlock) is modules/comfyui-vm.nix.
{
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # ComfyUI + the INT8 node are moving targets (the node wants "latest
  # ComfyUI and PyTorch cu130"), so they're git-cloned and pip-installed
  # INSIDE the guest on first boot rather than nix-packaged: unpinned and
  # unreproducible, but the whole point of this VM is that the mess — pip's
  # and the models' — stays on the data disk. Idempotent: re-runs are no-ops,
  # `rm /data/venv/.setup-done` forces a redo, `git -C /data/ComfyUI pull` updates.
  comfyRun = pkgs.writeShellScript "comfy-run" ''
    set -euo pipefail
    cd /data
    [ -d ComfyUI ] || git clone https://github.com/comfyanonymous/ComfyUI
    [ -d ComfyUI/custom_nodes/ComfyUI-INT8-Fast ] || \
      git clone https://github.com/BobJohnson24/ComfyUI-INT8-Fast \
        ComfyUI/custom_nodes/ComfyUI-INT8-Fast
    if [ ! -f venv/.setup-done ]; then
      [ -d venv ] || python3 -m venv venv
      ./venv/bin/pip install --upgrade pip
      # cu130 per the INT8-Fast README; torch's own dep pulls the matching
      # triton, so no separate triton install (a bare `pip install triton`
      # could drag in a version torch wasn't built against).
      ./venv/bin/pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu130
      ./venv/bin/pip install -r ComfyUI/requirements.txt
      if [ -f ComfyUI/custom_nodes/ComfyUI-INT8-Fast/requirements.txt ]; then
        ./venv/bin/pip install -r ComfyUI/custom_nodes/ComfyUI-INT8-Fast/requirements.txt
      fi
      touch venv/.setup-done
    fi
    exec ./venv/bin/python ComfyUI/main.py --listen 0.0.0.0 --port 8188
  '';

  # manylinux wheels (torch, triton, opencv, …) expect an FHS world; this is
  # the standard NixOS recipe for running them. gcc/binutils are here because
  # triton JIT-compiles kernels at runtime and shells out to `cc`.
  comfyFhs = pkgs.buildFHSEnv {
    name = "comfy-fhs";
    targetPkgs =
      p: with p; [
        python312
        git
        gcc
        binutils
        zlib
        openssl
        glib
        libGL
        libglvnd
        stdenv.cc.cc.lib # libstdc++ for the wheels' native bits
      ];
    # default runScript is bash; `comfy-fhs <script>` == bash <script> inside FHS
  };
in
{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  virtualisation = {
    # No root image — tmpfs / + RO 9p store, exactly like dispvm.
    # The persistent data disk is NOT declared here: the runner attaches it
    # via QEMU_OPTS (path is a host-side concern), guest mounts it by label.
    diskImage = null;
    # Host has 31 GiB; win11 is guaranteed not to be running concurrently
    # (same GPU), so taking 20 GiB is fine. INT8-quantized Krea2-class
    # checkpoints want lots of RAM while loading; guest zram below is the
    # safety margin.
    memorySize = 20480; # MiB
    cores = 12;
    # ComfyUI web UI: guest 8188 -> host 127.0.0.1:8188 (loopback only).
    forwardPorts = [
      {
        from = "host";
        host.port = 8188;
        guest.port = 8188;
      }
    ];
    # PCIe machine type for the passthrough GPU. qemu-common.nix already
    # passes `-machine accel=kvm`; repeated -machine flags merge, so this
    # just sets the type. The vfio-pci device itself comes from the runner
    # (QEMU_OPTS) so the VM can also boot GPU-less for smoke tests.
    qemu.options = [ "-machine q35" ];
  };

  # ── The one persistent thing: the data disk ──────────────────────────────
  # Runner creates it as a raw sparse file, mkfs.ext4 -L comfy-data, and
  # attaches it virtio; by-label keeps this independent of vda/vdb ordering.
  # nofail: a run without the disk attached still boots (setup will fail
  # loudly in the comfyui unit instead of hanging boot).
  # NB: must be virtualisation.fileSystems — qemu-vm.nix sets the plain
  # fileSystems option with mkVMOverride, which silently DISCARDS ordinary
  # fileSystems.* definitions (verified: data.mount didn't exist).
  virtualisation.fileSystems."/data" = {
    device = "/dev/disk/by-label/comfy-data";
    fsType = "ext4";
    options = [
      "nofail"
      "discard" # keep the host-side sparse file sparse when models get deleted
    ];
  };

  # ── NVIDIA driver for the passed-through 3080 (GA102 => open modules) ────
  nixpkgs.config.allowUnfree = true;
  hardware.graphics.enable = true;
  # mkVMOverride needed for the same reason as the /data mount above:
  # qemu-vm.nix pins videoDrivers to [ "modesetting" ] at mkVMOverride
  # priority, which would silently drop the nvidia driver (and with it CUDA).
  services.xserver.videoDrivers = lib.mkVMOverride [ "nvidia" ]; # loads the driver; no X runs
  hardware.nvidia.open = true;
  # CUDA needs nvidia_uvm and doesn't always autoload it; harmless no-op
  # when booted --no-gpu (modules-load failures are non-fatal).
  boot.kernelModules = [ "nvidia_uvm" ];

  # Headroom for model loading spikes; disk swap doesn't exist here.
  zramSwap.enable = true;

  systemd.services.comfyui = {
    description = "ComfyUI (venv on /data, FHS env)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # requires data.mount: with nofail above, a missing disk fails THIS unit
    # with a clear message instead of half-running against tmpfs.
    requires = [ "data.mount" ];
    after = [
      "network-online.target"
      "data.mount"
    ];
    environment = {
      LD_LIBRARY_PATH = "/run/opengl-driver/lib"; # libcuda for torch/triton
      # keep every cache on the persistent disk — comfy's $HOME is tmpfs
      HF_HOME = "/data/.cache/huggingface";
      PIP_CACHE_DIR = "/data/.cache/pip";
      TRITON_CACHE_DIR = "/data/.cache/triton";
      TORCHINDUCTOR_CACHE_DIR = "/data/.cache/inductor";
    };
    serviceConfig = {
      User = "comfy";
      Group = "users";
      WorkingDirectory = "/data";
      # "+" = run as root: the fresh ext4 is root-owned on first boot
      ExecStartPre = "+${pkgs.coreutils}/bin/chown comfy:users /data";
      ExecStart = "${comfyFhs}/bin/comfy-fhs ${comfyRun}";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  users.users.comfy.isNormalUser = true;

  # Console on the serial socket, root, no password: admin/debug surface for a
  # single-user local VM (download models, watch logs). Not reachable from
  # the network — sshd is off, only 8188 is forwarded.
  services.getty.autologinUser = "root";
  # The console is a socket chardev (`comfy` attaches with socat): every
  # client disconnect drops carrier on ttyS0, hanging up the session, and an
  # unattended boot can churn agetty into systemd's default start limit —
  # leaving the console permanently dead until you'd systemctl reset-failed
  # it blind. Let it retry forever; agetty blocks waiting for carrier, so
  # this doesn't spin while nobody is attached.
  systemd.services."serial-getty@ttyS0" = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.Restart = "always";
  };
  users.motd = ''
    ComfyUI VM — UI at http://localhost:8188 on the host (first boot
    pip-installs torch cu130 etc: several GB, watch `journalctl -fu comfyui`).
    Models    -> /data/ComfyUI/models/...   (download here, e.g. `aria2c -x8 <url>`)
    Node      -> /data/ComfyUI/custom_nodes/ComfyUI-INT8-Fast
    Update    -> git -C /data/ComfyUI pull   (+ rm /data/venv/.setup-done to re-pip)
    GPU check -> nvidia-smi / nvtop
    To host   -> `comfy serve` on the host, then here:
                 python3 -m http.server 8000 -d /data/ComfyUI/output
  '';
  environment.systemPackages = with pkgs; [
    git
    wget
    aria2
    pciutils
    htop
    nvtopPackages.nvidia
    python3 # ad-hoc file serving to the host (the venv python only exists inside the FHS env)
  ];

  # 8000: file serving to the host (`comfy serve` in aliases.fish). Open here
  # is harmless on its own — slirp has no inbound path until the runner or the
  # monitor adds a hostfwd, and those bind host-loopback only.
  networking.firewall.allowedTCPPorts = [
    8188
    8000
  ];

  networking.hostName = "comfyui"; # names the runner: run-comfyui-vm
  # Guest is rebuilt from scratch every boot (tmpfs root); this only pins
  # option defaults.
  system.stateVersion = "26.05";
}
