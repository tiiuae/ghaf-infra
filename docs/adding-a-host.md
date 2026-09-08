<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Adding a New Host

To add a NixOS host to ghaf-infra, follow the steps below. See also
[architecture.md](./architecture.md).

## Prerequisites

- Server provisioned with an IP address
- SSH access as root to the target machine
- Your age key listed in `.sops.yaml` (you are an admin)
- `nix develop` shell active

## File checklist

The examples below target an x86_64 Hetzner Cloud VM using legacy BIOS and
use `ghaf-example` as the host name. Replace it with the actual name. For
other platforms, start from a host with the same hardware and boot mode. See
[`hosts/ghaf-webserver/`](../hosts/ghaf-webserver/) for a minimal reference.

### 1. Create the host configuration

Create `hosts/<name>/configuration.nix`. Import the `common` module, any
service modules the host needs, and user modules:

```nix
# hosts/ghaf-example/configuration.nix
{ self, inputs, ... }:
{
  imports = [
    ./disk-config.nix
    self.nixosModules.hetzner-cloud
    inputs.disko.nixosModules.disko
  ]
  ++ (with self.nixosModules; [
    common
    openssh
    team-devenv
    # add other service modules as needed
  ]);

  sops.defaultSopsFile = ./secrets.yaml;

  system.stateVersion = "<nixpkgs-release>";
  networking.hostName = "ghaf-example";

  services.monitoring = {
    metrics.enable = true;
    logs.enable = true;
  };
}
```

The `hetzner-cloud` module selects GRUB for legacy BIOS and supplies the
QEMU guest and network defaults. The disk layout below includes the `EF02`
partition needed by GRUB. The `common` module imports sops-nix.

The `team-devenv` import provides admin users with SSH keys and sudo access.
Use the appropriate user or team module for the new host; `openssh` disables
root login.

For a new install, replace `<nixpkgs-release>` with the pinned release:

```sh
nix eval --raw .#nixosConfigurations.ghaf-webserver.config.system.nixos.release
```

`inv install` warns if `system.stateVersion` differs. Keep the chosen value on
subsequent upgrades; it records the release used for the initial installation.
Adapt the boot and network settings to the target hardware before installing.

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

### 3. Add the host to `hosts/machines.nix`

Add a new inventory entry with the module path, target system, and machine
metadata such as the public IP and the assigned Hetzner private network IP:

```nix
ghaf-example = {
  module = ./ghaf-example/configuration.nix;
  system = "x86_64-linux";
  machine = {
    ip = "1.2.3.4";
    internal_ip = "<private-ip>";
  };
};
```

This file drives `flake.nixosConfigurations.*` and `nix/deployments.nix`
automatically. For normal hosts, `system` also drives `nixpkgs.hostPlatform`,
so it does not need to be restated in the host config. VMs or other
non-deploy-rs hosts can omit the `machine` attrset; VM-style outliers should
also set `kind = "vm"`. The `publicKey` field is populated after the first
install (see [print-keys](./tasks.md#print-keys)).

#### Configure monitoring

The example enables node-exporter and sends journal logs to Loki. Attach
the VM to the same Hetzner private network as `ghaf-monitoring` and replace
`<private-ip>` with its assigned address. The `hetzner-cloud` module supplies
the internal Loki URL and trusts the private interface, `eth1`.

Add the host to `hetznerCloudHosts` in
[`hosts/ghaf-monitoring/configuration.nix`](../hosts/ghaf-monitoring/configuration.nix)
so Prometheus scrapes it. Deploy `ghaf-monitoring` after the new host is
running to apply the target change. For other environments, configure the
appropriate scrape job, network access, and Loki endpoint and credentials;
see [Monitoring](./monitoring.md#hosts).

## Provisioning (first install)

Create the encrypted file referenced by `sops.defaultSopsFile` before
installing. Add a creation rule to `.sops.yaml` using your existing admin
key anchor; the host's key will be added after its first boot:

```yaml
- path_regex: hosts/ghaf-example/secrets.yaml$
  key_groups:
  - age:
    - *your-admin-anchor
```

Open the new secrets file with sops:

```sh
sops hosts/ghaf-example/secrets.yaml
```

Replace the editor's example contents with `bootstrap: pending-host-key`
and save. Leave `ssh_host_ed25519_key` absent until the host generates it.

Stage the new files so the Git flake includes them:

```sh
git add hosts/ghaf-example/configuration.nix hosts/ghaf-example/disk-config.nix hosts/machines.nix
git add .sops.yaml hosts/ghaf-example/secrets.yaml
```

Install the host with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere):

```sh
inv install --alias ghaf-example
```

This repartitions the disk and deploys the NixOS configuration.
**All existing data on the target will be destroyed.**

The first install uses this placeholder (`inv install` will warn that
reading `ssh_host_ed25519_key` failed; confirm with `y` to continue). NixOS
generates an SSH host key on first boot. Those keys are captured in the
next section.

## Setting up secrets

After the first install the host has generated its SSH host key. The
following steps retrieve that key, add it to sops, and redeploy so the
host receives its encrypted secrets.

### 4. Add host age key to `.sops.yaml`

Retrieve the host's SSH public key and convert it to an age key:

```sh
ssh-keyscan -t ed25519 <host-ip> | ssh-to-age
```

Add the resulting age key to the `keys` section of `.sops.yaml`:

```yaml
- &ghaf-example age1...
```

### 5. Update the creation rule in `.sops.yaml`

Add the host's key to the existing `creation_rules` entry:

```yaml
- path_regex: hosts/ghaf-example/secrets.yaml$
  key_groups:
  - age:
    - *ghaf-example
    - *your-admin-anchor
```

### 6. Store the host key in the secrets file

Copy the host's private SSH key from the remote host and store it as
a sops secret:

```sh
# Copy the private key from the host (requires sudo; root login is disabled)
(umask 077 && ssh <user>@<host-ip> sudo cat /etc/ssh/ssh_host_ed25519_key > /tmp/host-key)

sops hosts/ghaf-example/secrets.yaml
```

In the sops editor, remove `bootstrap` and paste the complete contents of
`/tmp/host-key` under `ssh_host_ed25519_key: |`. Indent every key line by two
spaces, including the BEGIN and END lines, to preserve the newlines:

```yaml
ssh_host_ed25519_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <paste all key lines here>
  -----END OPENSSH PRIVATE KEY-----
```

Save and close the editor, then remove the plaintext copy:

```sh
# Remove the temporary key file
rm /tmp/host-key
```

At minimum, the secrets file must contain the `ssh_host_ed25519_key`.
Stage the encrypted file so Nix can read it:

```sh
git add hosts/ghaf-example/secrets.yaml
```

Use `inv print-keys --alias ghaf-example` to read the stored public key, and
add it as `machine.publicKey` in `hosts/machines.nix`.

### 7. Run `inv update-sops-files`

Re-encrypt all sops files to reflect the updated `.sops.yaml` rules:

```sh
inv update-sops-files
```

### 8. Redeploy with secrets

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
