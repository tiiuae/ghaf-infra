# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  config,
  pkgs,
  inputs,
  lib,
  machines,
  options,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    zramSwap
    jenkins
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

  services.ghaf-jenkins = {
    enable = true;
    # Keep in sync with Ghaf's .github/workflows/source-vsa.yml issuer pin.
    sourceVsa.trustedWorkflowSha = "660e93c77e9840cf36278aef81ec39ec8a1ad7b2";
    remoteStores = builtins.listToAttrs (
      map (builder: {
        name = builder.system;
        value =
          "${builder.protocol}://"
          + lib.optionalString (builder.sshUser != null) "${builder.sshUser}@"
          + builder.hostName
          +
            lib.optionalString (builder.sshKey != null)
              "${if lib.hasInfix "?" builder.hostName then "&" else "?"}ssh-key=${builder.sshKey}";
      }) config.nix.buildMachines
    );
    registry.enable = true;
    registry.url = lib.mkDefault "registry.vedenemo.dev";
    provenanceTrustPolicyFile = ../../slsa/provenance-trust-policy.yaml;
    releasePolicyFile = ../../slsa/release-policy.yaml;
    auth = {
      oidcIssuerUrl = lib.mkDefault "https://auth.vedenemo.dev";
      groups = {
        authenticated = [
          "Overall/Read"
          "Job/Read"
        ];
        "tiiuae:devenv-fi" = [ "Overall/Administer" ];
        "tiiuae:ci-dev-admins" = [
          "Overall/Read"
          "Overall/SystemRead"
          "Job/Build"
          "Job/Cancel"
          "Job/Read"
          "Job/Configure"
          "Run/Replay"
          "Run/Update"
        ];
      };
    };
    agents =
      lib.genAttrs
        [
          "testagent-dev"
          "testagent-dbg"
          "testagent2-prod"
          "testagent-prod"
          "testagent-release"
          "uae-testagent-prod"
          "uae-testagent2-prod"
        ]
        (name: {
          inherit (self.nixosConfigurations.${name}.config.services.testagent) variant devices nodeNamePrefix;
          publicKey = machines.${name}.publicKey;
          enable = lib.mkDefault false;
        });
  };

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
}
