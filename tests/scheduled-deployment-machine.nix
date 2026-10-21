# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  modulesPath,
  testRevision,
  testVariant,
  ...
}:
{
  imports = [
    ../modules/scheduled-deployment
    ../modules/monitoring.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
    (modulesPath + "/testing/test-instrumentation.nix")
  ];
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "machine";
  networking.useDHCP = false;
  system.stateVersion = "26.05";
  system.configurationRevision = testRevision;
  system.nixos = {
    revision = lib.mkForce "constant-nixos-revision";
    versionSuffix = lib.mkForce "test";
    label = lib.mkForce "test";
  };
  documentation.nixos.enable = false;
  services.openssh.enable = true;
  services.monitoring.metrics.enable = true;
  services.scheduled-deployment = {
    enable = true;
    repository = "file:///repo";
    postDeployChecks = if testVariant == "bad" then "exit 1" else "test -e /etc/test-generation";
  };
  environment.etc."test-generation".text = testVariant;
  environment.systemPackages = [ pkgs.gitMinimal ];
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = lib.mkForce [ ];
    hashed-mirrors = null;
    flake-registry = "";
  };
  virtualisation = {
    useBootLoader = true;
    fileSystems."/".autoResize = true;
    memorySize = 2048;
    diskSize = 20480;
  };
  boot.initrd.systemd.enable = true;
  boot.growPartition = true;
  boot.initrd.systemd.contents."/test-reboot" = lib.mkIf (testVariant == "reboot") {
    text = "changed initrd";
  };
  # All runs in the test are explicit; the boot verification timer stays enabled.
  systemd.timers.scheduled-deployment.wantedBy = lib.mkForce [ ];
  systemd.timers.scheduled-deployment-verify.timerConfig.OnBootSec = lib.mkForce "5s";
}
