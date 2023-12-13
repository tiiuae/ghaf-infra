# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
#
# SPDX-License-Identifier: Apache-2.0
{
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        azure-cli
        git
        jq
        nix
        nixos-rebuild
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
        (terraform.withPlugins (p: [
          p.azurerm
          p.external
          p.null
          p.random
          p.sops
        ]))
      ];
    };
  };
}
