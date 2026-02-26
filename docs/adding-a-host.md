<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Adding a New Host

This runbook covers the end-to-end steps for adding a new NixOS host to
ghaf-infra. For architectural context on where hosts fit, see
[architecture.md](./architecture.md).

## Prerequisites

- Server provisioned with an IP address
- SSH access as root to the target machine
- Your age key listed in `.sops.yaml` (you are an admin)
- `nix develop` shell active

## File checklist

The following files need to be created or modified. The examples below use
`ghaf-example` as the host name — replace it with the actual name. See
[`hosts/ghaf-webserver/`](../hosts/ghaf-webserver/) for a minimal reference.

### 1. Create the host configuration

Create `hosts/<name>/configuration.nix`. Import the `common` module, any
service modules the host needs, and user modules:

```nix
# hosts/ghaf-example/configuration.nix
{ self, lib, inputs, ... }:
{
  imports = [
    ./disk-config.nix
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    service-openssh
    # add other service modules as needed
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = lib.mkForce "24.05";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ghaf-example";
}
```

### 2. Create the disk configuration

Create `hosts/<name>/disk-config.nix` with [disko](https://github.com/nix-community/disko)
partitioning for the target disk. Identify the disk device ID on the server
(e.g. via `ls /dev/disk/by-id/`):

```nix
# hosts/ghaf-example/disk-config.nix
{
  disko.devices.disk.os = {
    device = "/dev/disk/by-id/<disk-id>";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { type = "EF02"; size = "1M"; };
        ESP = {
          type = "EF00"; size = "512M";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
```

### 3. Add entry to `hosts/machines.nix`

Add the host's IP (and optionally `internal_ip`, `nebula_ip`, `publicKey`):

```nix
ghaf-example = {
  ip = "1.2.3.4";
};
```

The `publicKey` field is populated after the first install (see
[print-keys](./tasks.md#print-keys)).

### 4. Add NixOS module to `hosts/default.nix`

In the `flake.nixosModules` attrset, add:

```nix
nixos-ghaf-example = ./ghaf-example/configuration.nix;
```

### 5. Add to nixosConfigurations list

In the same file, add `"ghaf-example"` to the list passed to `builtins.map`.

### 6. Add deploy-rs node to `nix/deployments.nix`

Add the host to the appropriate node set (`x86-nodes` or `aarch64-nodes`):

```nix
ghaf-example = mkDeployment "ghaf-example" machines.ghaf-example.ip;
```

## Provisioning (first install)

Install the host with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere):

```sh
inv install --alias ghaf-example
```

This repartitions the disk and deploys the NixOS configuration.
**All existing data on the target will be destroyed.**

The first install runs without host-specific secrets (`inv install` will
warn that decryption failed — confirm with `y` to continue). NixOS
generates an SSH host key on first boot. Those keys are captured in the
next section.

## Setting up secrets

After the first install the host has generated its SSH host key. The
following steps retrieve that key, add it to sops, and redeploy so the
host receives its encrypted secrets.

### 7. Add host age key to `.sops.yaml`

Retrieve the host's SSH public key and convert it to an age key:

```sh
ssh-keyscan -t ed25519 <host-ip> | ssh-to-age
```

Add the resulting age key to the `keys` section of `.sops.yaml`:

```yaml
- &ghaf-example age1...
```

### 8. Add creation rule in `.sops.yaml`

Add a `creation_rules` entry so sops knows which keys can decrypt the
host's secrets:

```yaml
- path_regex: hosts/ghaf-example/secrets.yaml$
  key_groups:
  - age:
    - *ghaf-example
    - *your-admin-anchor
```

### 9. Create secrets file

Copy the host's private SSH key from the remote host and store it as
a sops secret:

```sh
# Copy the private key from the host (requires sudo — root login is disabled)
(umask 077 && ssh <user>@<host-ip> sudo cat /etc/ssh/ssh_host_ed25519_key > /tmp/host-key)

# Create the encrypted secrets file and add the key as ssh_host_ed25519_key
sops hosts/ghaf-example/secrets.yaml

# Remove the temporary key file
rm /tmp/host-key
```

At minimum, the secrets file must contain the `ssh_host_ed25519_key`.

### 10. Run `inv update-sops-files`

Re-encrypt all sops files to reflect the updated `.sops.yaml` rules:

```sh
inv update-sops-files
```

### 11. Redeploy with secrets

Deploy the configuration again so the host receives its secrets
(see [deploy-rs.md](./deploy-rs.md)):

```sh
deploy .#ghaf-example
```

## Post-install

Verify the deployment:

```sh
inv print-revision --alias ghaf-example
```

For subsequent configuration changes, deploy with
[deploy-rs](./deploy-rs.md):

```sh
deploy .#ghaf-example
```

## Optional: Nebula enrollment

If the host needs to join the Nebula overlay network, follow the
[Nebula onboarding checklist](./nebula.md#onboarding-checklist).
