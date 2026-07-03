{ config, pkgs, ... }:

{
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];
  boot.initrd.kernelModules = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    # Old config used .beta; stable is the sane default for a fresh install.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true; # open kernel module, correct for Turing (RTX 20xx) and newer
    nvidiaSettings = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
  };

  # Note: dropped the PRIME render-offload env vars from the old config
  # (NV_PRIME_RENDER_OFFLOAD etc.) — those are for dual-GPU laptops.
}
