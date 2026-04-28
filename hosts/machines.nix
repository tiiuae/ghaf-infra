# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Inventory schema:
# - module: path to the host configuration module.
# - system: nixpkgs host platform for mkNixOS and deploy-rs grouping.
# - machine: optional deploy/install metadata (ip, internal_ip, nebula_ip, publicKey).
# - kind: optional; set to "vm" for outliers that should not be auto-generated via mkNixOS.
{
  hetzarm = {
    module = ./builders/hetzarm/configuration.nix;
    system = "aarch64-linux";
    machine = {
      ip = "65.21.20.242";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILx4zU4gIkTY/1oKEOkf9gTJChdx/jR3lDgZ7p/c7LEK";
    };
  };

  hetzarm-dbg-1 = {
    module = ./builders/hetzarm-dbg-1/configuration.nix;
    system = "aarch64-linux";
    machine = {
      ip = "46.62.194.107";
      internal_ip = "10.0.0.14";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3y9z/2FWQdM9nnUJSc8bdsXApC0ug/ttdOGM/r2Zoq";
    };
  };

  hetzarm-rel-1 = {
    module = ./builders/hetzarm-rel-1/configuration.nix;
    system = "aarch64-linux";
    machine = {
      ip = "46.62.196.166";
      internal_ip = "10.0.0.12";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/4rUvG9LPsYGuPFIwjJLoip/DOa6NTWUPGQ20fxXFy";
    };
  };

  testagent-dbg = {
    module = ./testagent/dbg/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.18.16.26";
      nebula_ip = "10.42.42.15";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3w98CfNka5zctBY5NJfOjKuvCjB7rJ8mSqg8EHoh/F";
    };
  };

  testagent-prod = {
    module = ./testagent/prod/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.18.16.60";
      nebula_ip = "10.42.42.12";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXYn8XEtZ/LoRBnM/GwNJMg0gcpFMEYEyQX3X9DTENx";
    };
  };

  testagent-dev = {
    module = ./testagent/dev/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.18.16.33";
      nebula_ip = "10.42.42.11";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVZVd2ZBBHBYCJVOhjhfVXi4lrVYtcH5CkQjTqBfg/4";
    };
  };

  testagent2-prod = {
    module = ./testagent/prod2/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.18.16.25";
      nebula_ip = "10.42.42.14";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhiyhuoKlkkzxXDYhzfa/lnchwWMt/GokyIk1lBhQD6";
    };
  };

  testagent-release = {
    module = ./testagent/release/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.18.16.32";
      nebula_ip = "10.42.42.13";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP2xRl4jtu1ARpyj9W3uEo+GACLywosKhal432CgK+H";
    };
  };

  nethsm-gateway = {
    module = ./nethsm-gateway/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "192.168.70.11";
      nebula_ip = "10.42.42.20";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGShuT9oEIq5SQ3lo6n/gT1/OQ3TeJ2r53UUAlWYPJoB";
    };
  };

  ghaf-log = {
    module = ./ghaf-log/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "95.217.177.197";
      internal_ip = "10.0.0.7";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICMmB3Ws5MVq0DgVu+Hth/8NhNAYEwXyz4B6FRCF6Nu2";
    };
  };

  ghaf-webserver = {
    module = ./ghaf-webserver/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "37.27.204.82";
      internal_ip = "10.0.0.8";
    };
  };

  ghaf-auth = {
    module = ./ghaf-auth/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "37.27.190.109";
      internal_ip = "10.0.0.4";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPc04ZyZ7LgUKhV6Xr177qQn6Vf43FzUr1mS6g3jrSDj";
    };
  };

  ghaf-monitoring = {
    module = ./ghaf-monitoring/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "135.181.103.32";
      internal_ip = "10.0.0.2";
      nebula_ip = "10.42.42.2";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4gFTuMYnoOpDrknKhD2qlBhsCLiR00K7dpRfmm14F7";
    };
  };

  ghaf-lighthouse = {
    module = ./ghaf-lighthouse/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "65.109.141.136";
      internal_ip = "10.0.0.10";
      nebula_ip = "10.42.42.1";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9dKZmXqN8in6/0jglv+/txjWRkRJkPOUSVUGTx6KaG";
    };
  };

  ghaf-fleetdm = {
    module = ./ghaf-fleetdm/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "95.216.169.87";
      internal_ip = "10.0.0.13";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILohl64vKdsBX3x8SkKjJDphXEYTJGpnE1mHQYERUXZM";
    };
  };

  ghaf-registry = {
    module = ./ghaf-registry/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "89.167.65.27";
      internal_ip = "10.0.0.14";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMGfy1TgAnHfOFqVXDmSdYM60fInNKYOo4Bmf2T6Q8mC";
    };
  };

  hetzci-dbg = {
    module = ./hetzci/dbg/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "95.216.200.85";
      internal_ip = "10.0.0.3";
      nebula_ip = "10.42.42.6";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALs+OQDrCKRIKkwTwI4MI+oYC3RTEus9cXCBcIyRHzl";
    };
  };

  hetzci-dev = {
    module = ./hetzci/dev/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "157.180.119.138";
      internal_ip = "10.0.0.6";
      nebula_ip = "10.42.42.3";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ8XgXW7leM8yIOyU86aDztcWBGKkBAgTiu5yaAcJcvD";
    };
  };

  hetzci-prod = {
    module = ./hetzci/prod/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "157.180.43.236";
      internal_ip = "10.0.0.5";
      nebula_ip = "10.42.42.4";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBdDmtt7At/xDNCF0aIDvXc2T9GTP0HWaAt4DEAejcE6";
    };
  };

  hetzci-release = {
    module = ./hetzci/release/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "95.217.210.252";
      internal_ip = "10.0.0.9";
      nebula_ip = "10.42.42.5";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILt+qbA7j8q+CjiAY2vX1rEhH3ow4xRKqyMszVI0zvmm";
    };
  };

  hetzci-vm = {
    kind = "vm";
    module = ./hetzci/vm/configuration.nix;
    system = "x86_64-linux";
  };

  hetz86-1 = {
    module = ./builders/hetz86-1/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "37.27.170.242";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG05U1SHacBIrp3dH7g5O1k8pct/QVwHfuW/TkBYxLnp";
    };
  };

  hetz86-builder = {
    module = ./builders/hetz86-builder/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "65.108.7.79";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68NdmOw3mhiBZwDv81dXitePoc1w//p/LpsHHA8QRp";
    };
  };

  hetz86-dbg-1 = {
    module = ./builders/hetz86-dbg-1/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "46.62.194.110";
      internal_ip = "10.0.0.11";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGg4+l1ln0HycoqkN0vbwvU+fZBniozhLq0Z8hGsGfjx";
    };
  };

  hetz86-rel-2 = {
    module = ./builders/hetz86-rel-2/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "65.21.200.168";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPG/KEdKxs3ws7aoHSar4UqK7RzmAGa8j9Xug6Eo7VMm";
    };
  };

  uae-lab-node1 = {
    module = ./uae/lab/node1/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.31.107.42";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINXec/ZGWCbBTaSi4dYOhVMWt/BUlSaIuvU/k9Ciap3P";
    };
  };

  uae-nethsm-gateway = {
    module = ./uae/nethsm-gateway/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.31.141.51";
      nebula_ip = "10.42.42.33";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ69aPBjri8UJi1KbVDEUYW5YeHzAkQ86acQNHzqyrD0";
    };
  };

  uae-azureci-prod = {
    module = ./uae/azureci/prod/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "74.162.68.205";
      nebula_ip = "10.42.42.34";
      internal_ip = "10.51.16.4";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgPq27pnOcNPRnYBCZpsOyHfRhhtWU2EiUQFUHZCqev";
    };
  };

  uae-azureci-az86-1 = {
    module = ./uae/azureci/builders/az86-1/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "20.46.48.30";
      internal_ip = "10.51.16.5";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23fArR5mkx9eCHVKZ2EN/fqxR5LcXKkz4e8DSwLwG+";
    };
  };

  uae-testagent-prod = {
    module = ./uae/testagent/prod/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.20.16.24";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHO30maPQbVUqURaur8ze2S0vrrUivj2QdItIHsK75RS";
    };
  };

  uae-azureci-hetzarm-1 = {
    module = ./uae/azureci/builders/hetzarm-1/configuration.nix;
    system = "aarch64-linux";
    machine = {
      ip = "91.98.90.243";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDP8yHa00zzjb+KSLB/pSZTKsAiU4vW1V75dqS1/6TqZ";
    };
  };

  uae-testagent2-prod = {
    module = ./uae/testagent/prod2/configuration.nix;
    system = "x86_64-linux";
    machine = {
      ip = "172.20.16.25";
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBxyeOZsaqhiDREmVU+H8sUIiCmg6JgjDdbAvFpDx+KI";
    };
  };
}
