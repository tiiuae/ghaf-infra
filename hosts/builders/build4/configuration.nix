# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self, ...}: {
  imports =
    [
      ../ficolo.nix
      ../cross-compilation.nix
      ../yubikey.nix
    ]
    ++ (with self.nixosModules; [
      user-themisto
      service-nginx
    ]);

  # build4 specific configuration

  networking.hostName = "build4";

  users.users.yubimaster.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2BcpFzSXOuK9AzN+J1HBVnuVV8D3wgdEwPuILNy2aM signer"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "trash@unikie.com";
  };

  services.nginx = {
    virtualHosts = {
      "pandia.vedenemo.dev" = {
        enableACME = true;
        forceSSL = true;
        default = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3015";
        };
      };
    };
  };
}
