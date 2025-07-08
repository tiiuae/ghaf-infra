# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  perSystem =
    {
      pkgs,
      inputs',
      config,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
          FLAKE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
          if [ -z "$FLAKE_ROOT" ]; then
            echo "WARNING: flake root not round; skipping helpers installation."
            return
          fi
          prefetch-plugins-azure-controller () {
            python "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/hosts/azure/jenkins-controller/plugins.txt \
              --output "$FLAKE_ROOT"/hosts/azure/jenkins-controller/plugins.json
          }
          prefetch-plugins-hetzci-prod () {
            python "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/hosts/hetzci/prod/plugins.txt \
              --output "$FLAKE_ROOT"/hosts/hetzci/prod/plugins.json
          }
          prefetch-plugins-hetzci-dev () {
            python "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/hosts/hetzci/dev/plugins.txt \
              --output "$FLAKE_ROOT"/hosts/hetzci/dev/plugins.json
          }
          prefetch-plugins-hetzci-vm () {
            python "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/hosts/hetzci/vm/plugins.txt \
              --output "$FLAKE_ROOT"/hosts/hetzci/vm/plugins.json
          }
          echo ""
          echo 1>&2 "Welcome to the development shell!"
          echo ""
          echo "This shell provides following helper commands:"
          echo " - prefetch-plugins-azure-controller"
          echo " - prefetch-plugins-hetzci-dev"
          echo " - prefetch-plugins-hetzci-prod"
          echo " - prefetch-plugins-hetzci-vm"
          echo ""
        '';

        packages =
          (with pkgs; [
            go
            azure-cli
            git
            jq
            nix
            nixfmt-rfc-style
            nixos-rebuild
            nixos-anywhere
            python3.pkgs.black
            python3.pkgs.colorlog
            python3.pkgs.deploykit
            python3.pkgs.invoke
            python3.pkgs.pycodestyle
            python3.pkgs.pylint
            python3.pkgs.tabulate
            python3.pkgs.aiohttp
            reuse
            sops
            ssh-to-age
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
              p.sops
            ]))
          ])
          ++ (with inputs'; [
            nix-fast-build.packages.default
            deploy-rs.packages.default
          ]);
      };
    };
}
