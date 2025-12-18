# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
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
          prefetch-plugins () {
            conf_path="$1"
            if [ -z "$conf_path" ]; then
              echo "Error: missing first argument - expecting relative path to host configuration"
              return
            fi
            python "$FLAKE_ROOT"/scripts/resolve_plugins.py \
              --jenkins-version ${pkgs.jenkins.version} \
              --plugins-file "$FLAKE_ROOT"/"$conf_path"/plugins.txt \
              --output "$FLAKE_ROOT"/"$conf_path"/plugins.json
          }
          echo ""
          echo 1>&2 "Welcome to the development shell!"
          echo ""
          echo "This shell provides following helper commands:"
          echo " - prefetch-plugins hosts/hetzci"
          echo " - prefetch-plugins hosts/uae/azureci"
          echo ""
        '';

        packages =
          (with pkgs; [
            go
            git
            jq
            nix
            nixfmt-rfc-style
            nixos-rebuild
            nixos-anywhere
            python3.pkgs.aiohttp
            python3.pkgs.deploykit
            python3.pkgs.invoke
            python3.pkgs.loguru
            python3.pkgs.pycodestyle
            python3.pkgs.pylint
            python3.pkgs.tabulate
            reuse
            sops
            ssh-to-age
            wget
            nebula
            openssl
            gnutls
            minio-client
            tree
          ])
          ++ (with inputs'; [
            nix-fast-build.packages.default
            deploy-rs.packages.default
          ]);
      };
    };
}
