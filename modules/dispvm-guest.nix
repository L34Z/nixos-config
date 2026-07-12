# Qubes-style disposable VM: a fresh, amnesic Firefox for one session.
# `dispvm` (or the "Disposable Firefox" launcher entry) boots this config
# in QEMU with NO disk image: / is tmpfs, the host Nix store is shared
# read-only over 9p with a tmpfs overlay for writes — so every byte the
# guest writes lives and dies in RAM. Closing Firefox powers the VM off;
# closing the QEMU window kills it. Nothing to clean up afterwards.
#
# This is a GUEST NixOS config, built standalone via flake.nix
# (nixosConfigurations.disp + packages.dispvm). The host never imports it.
{ pkgs, modulesPath, ... }:

let
  # uBlock Origin, baked into the store and force-installed via enterprise
  # policy from a file:// URL — present instantly on every (first) boot, no
  # AMO fetch, and its default filter lists ship inside the XPI so blocking
  # works even offline. Bump: resolve the redirect of
  #   https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi
  # and update url + hash.
  ublock = pkgs.fetchurl {
    url = "https://addons.mozilla.org/firefox/downloads/file/4872816/ublock_origin-1.72.0.xpi";
    hash = "sha256-ec1CarWZgBxZ3+mJXLS4AC+vPaBZ9xEcJyGsEBaKO2Q=";
  };
  firefox = pkgs.firefox.override {
    extraPolicies = {
      ExtensionSettings."uBlock0@raymondhill.net" = {
        installation_mode = "force_installed";
        install_url = "file://${ublock}";
        # The session runs entirely in a private window; this is the
        # "Run in Private Windows: Allow" toggle (policy support: Fx 128+).
        private_browsing = true;
      };
    };
  };
in
{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  virtualisation = {
    # THE amnesia switch: no qcow2 is created or touched anywhere — the
    # qemu-vm module makes / a tmpfs when there is no disk image.
    diskImage = null;
    # tmpfs root, the writable-store overlay, and Firefox all live inside
    # this; the host only pays for pages actually used.
    memorySize = 8192; # MiB
    cores = 4;
    qemu.options = [
      # On x86 the qemu-vm module adds no display device, so qemu falls
      # back to an implicit 1024x768 stdvga. Replace it with virtio-gl at
      # the G7's native res — cage sizes its output to the preferred mode,
      # and virgl gives Firefox real GPU rendering (host side needs a
      # GL-capable display; the dispvm wrapper passes -display gtk,gl=on).
      # Headless runs must override with -display egl-headless, NOT none.
      "-vga none"
      "-device virtio-vga-gl,xres=2560,yres=1440"
    ];
  };

  # Guest-side GL (mesa/virgl) for the virtio-vga-gl device.
  hardware.graphics.enable = true;

  # Audio path: virtio-sound (added by the wrapper when the host has a
  # PipeWire socket) -> guest pipewire -> firefox via pipewire-pulse.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # Kiosk session: cage (single-window Wayland compositor) straight into a
  # private window. No display manager, no desktop, no other apps.
  services.cage = {
    enable = true;
    user = "disp";
    # services.cage.program is types.path, so args need a wrapper script.
    # `firefox` is the policy-wrapped package from the let-binding above.
    program = pkgs.writeShellScript "disp-firefox" ''
      exec ${firefox}/bin/firefox --private-window
    '';
    # Composite the cursor in the guest instead of using virtio-gpu's
    # hardware cursor plane: under gtk,gl=on that plane renders upside-down
    # and offset from the real pointer position (clicks land elsewhere).
    # Guest-drawn cursor = what you see is where you click.
    environment.WLR_NO_HARDWARE_CURSORS = "1";
  };
  # cage exits when Firefox does → power the VM off (Qubes dispvm behavior:
  # closing the app IS destroying the VM). OnFailure too, so a crashed
  # session can't linger as a headless zombie eating 8 GiB.
  systemd.services."cage-tty1".unitConfig = {
    OnSuccess = "poweroff.target";
    OnFailure = "poweroff.target";
  };

  users.users.disp.isNormalUser = true;

  networking.hostName = "disp"; # names the runner: run-disp-vm
  # The guest is stateless by construction, so this only pins option
  # defaults; it never marks real state.
  system.stateVersion = "26.05";
}
