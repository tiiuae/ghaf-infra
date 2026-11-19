# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, inputs, ... }:
{
  # Deliberately outside checks/packages: evaluated only when requested.
  # nix build -L .#tests.<name>
  flake.tests = {
    scheduled-deployment = import ./scheduled-deployment.nix { inherit (inputs) nixpkgs; };
    jenkins-controller-prod = import ./jenkins-controller.nix {
      inherit self;
      host = "hetzci-prod";
    };
    jenkins-controller-release = import ./jenkins-controller.nix {
      inherit self;
      host = "hetzci-release";
    };
    monitoring = import ./monitoring.nix { inherit self; };
    install-ghaf-lighthouse = import ./install.nix { inherit self; };
  };
}
