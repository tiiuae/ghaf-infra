# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  inputs,
  lib,
  machines,
  options,
  ...
}:
{
  imports = [
    self.nixosModules.zramSwap
    self.nixosModules.jenkins
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    openssh
    team-devenv
    team-testers
  ]);

  environment.systemPackages = with pkgs; [
    screen
    tmux
  ];

  # Increase the maximum number of open files user limit, see ulimit -n
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "-";
      value = "8192";
    }
  ];
  systemd.user =
    if options.systemd.user ? settings then
      {
        settings.Manager.DefaultLimitNOFILE = "8192";
      }
    else
      {
        extraConfig = "DefaultLimitNOFILE=8192";
      };

  # Enable early out-of-memory killing.
  # Make nix builds more likely to be killed over more important services.
  services.earlyoom = {
    enable = true;
    # earlyoom sends SIGTERM once below 5% and SIGKILL when below half
    # of freeMemThreshold
    freeMemThreshold = 5;
    extraArgs = [
      "--prefer"
      "^(nix-daemon)$"
      "--avoid"
      "^(java|jenkins-.*|sshd|systemd|systemd-.*)$"
    ];
  };

  services.ghaf-jenkins.enable = true;

  # Tell the Nix evaluator to garbage collect more aggressively
  environment.variables.GC_INITIAL_HEAP_SIZE = "1M";

  # Always overcommit: pretend there is always enough memory
  # until it actually runs out
  boot.kernel.sysctl."vm.overcommit_memory" = "1";

  nix.settings = {
    connect-timeout = 5;
    system-features = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    max-jobs = 0;
    builders-use-substitutes = true;

    min-free = lib.mkForce (70 * 1024 * 1024 * 1024);
    max-free = lib.mkForce (280 * 1024 * 1024 * 1024);
  };

  networking.firewall.allowedTCPPorts = [
    80
  ];

  # Users used by testagents to connect to Jenkins and collect their secrets.
  users.users = {
    testagent-dev = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.testagent-dev.publicKey ];
    };
    testagent-dbg = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.testagent-dbg.publicKey ];
    };
    testagent2-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.testagent2-prod.publicKey ];
    };
    testagent-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.testagent-prod.publicKey ];
    };
    testagent-release = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.testagent-release.publicKey ];
    };
    uae-testagent-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.uae-testagent-prod.publicKey ];
    };
    uae-testagent2-prod = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ machines.uae-testagent2-prod.publicKey ];
    };
  };
}
