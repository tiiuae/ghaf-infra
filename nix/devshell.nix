# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    { pkgs, inputs', ... }:
    {
      devShells.default = pkgs.mkShell {
        packages =
          (with pkgs; [
            azure-cli
            git
            jq
            nix
            nixfmt-rfc-style
            nixos-rebuild
            # parallel_env requires 'compgen' function, which is available
            # in bashInteractive, but not bash
            bashInteractive
            parallel
            python3.pkgs.black
            python3.pkgs.colorlog
            python3.pkgs.deploykit
            python3.pkgs.invoke
            python3.pkgs.pycodestyle
            python3.pkgs.pylint
            python3.pkgs.tabulate
            reuse
            sops
            ssh-to-age
            deploy-rs
            wget
            terragrunt
            (terraform.withPlugins (p: [
              # We need to override the azurerm version to fix the issue described
              # in https://ssrc.atlassian.net/browse/SP-4926.
              # TODO:
              # Below override is no longer needed when the azurerm version we
              # get from the nixpkgs pinned in ghaf-infra flake includes a fix for
              # https://github.com/hashicorp/terraform-provider-azurerm/issues/24444.
              # At the time of writing, ghaf-infra flake pins to
              # nixos-24.05, that ships with azurerm v3.97.1 which is broken.
              # For more information on the available azurerm versions, see:
              # https://registry.terraform.io/providers/hashicorp/azurerm.
              (p.azurerm.override {
                owner = "hashicorp";
                repo = "terraform-provider-azurerm";
                rev = "v3.85.0";
                hash = "sha256-YXVSApUnJlwxIldDoijl72rA9idKV/vGRf0tAiaH8cc=";
                vendorHash = null;
              })
              p.external
              p.local
              p.null
              p.random
              p.secret
              p.sops
              p.tls
            ]))
          ])
          ++ [
            inputs'.nix-fast-build.packages.default
            inputs'.jenkinsPlugins2nix.packages.jenkinsPlugins2nix
          ];
      };
    };
}
