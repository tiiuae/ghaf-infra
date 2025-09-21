<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tasks

Originally inspired by [nix-community infra](https://github.com/nix-community/infra) this project makes use of [pyinvoke](https://www.pyinvoke.org/) to help with deployment [tasks](../tasks.py).

All example commands in this document are executed in ghaf-infra nix devshell:
```bash
❯ nix develop
```

Run the following command to list the available tasks:

```bash
❯ inv --list
Available tasks:

  alias-list          List available targets (i.e. configurations and alias names)
  install             Install `alias` configuration using nixos-anywhere, deploying host private key.
  install-release     Initialize hetzner release environment
  print-keys          Decrypt host private key, print ssh and age public keys for `alias` config.
  reboot              Reboot host identified as `alias`.
  update-sops-files   Update all sops yaml and json files according to .sops.yaml rules.
```

In the following sections, we will explain the intended usage of the most common of the above deployment tasks.

## alias-list

The `alias-list` task lists the alias names for ghaf-infra targets. Alias is simply a name given for the combination of nixosConfig and hostname. All ghaf-infra tasks that need to identify a target, accept an alias name as an argument.

```bash
❯ inv alias-list

Current ghaf-infra targets:

╒═══════════════════╤═══════════════════╤═════════════════╕
│ alias             │ nixosconfig       │ hostname        │
╞═══════════════════╪═══════════════════╪═════════════════╡
│ ghaf-auth         │ ghaf-auth         │ 37.27.190.109   │
│ ghaf-lighthouse   │ ghaf-lighthouse   │ 65.109.141.136  │
│ ghaf-log          │ ghaf-log          │ 95.217.177.197  │
│ ghaf-monitoring   │ ghaf-monitoring   │ 135.181.103.32  │
│ ghaf-proxy        │ ghaf-proxy        │ 95.216.200.85   │
│ ghaf-webserver    │ ghaf-webserver    │ 37.27.204.82    │
│ hetz86-1          │ hetz86-1          │ 37.27.170.242   │
│ hetz86-builder    │ hetz86-builder    │ 65.108.7.79     │
│ hetz86-rel-1      │ hetz86-rel-1      │ 46.62.194.110   │
│ hetzarm           │ hetzarm           │ 65.21.20.242    │
│ hetzarm-rel-1     │ hetzarm-rel-1     │ 46.62.196.166   │
│ hetzci-dev        │ hetzci-dev        │ 157.180.119.138 │
│ hetzci-prod       │ hetzci-prod       │ 157.180.43.236  │
│ hetzci-release    │ hetzci-release    │ 95.217.210.252  │
│ nethsm-gateway    │ nethsm-gateway    │ 192.168.70.11   │
│ testagent-dev     │ testagent-dev     │ 172.18.16.33    │
│ testagent-prod    │ testagent-prod    │ 172.18.16.60    │
│ testagent-release │ testagent-release │ 172.18.16.32    │
│ testagent-uae-dev │ testagent-uae-dev │ 172.19.16.12    │
╘═══════════════════╧═══════════════════╧═════════════════╛

```

In case `hostname` is not directly accessible for your current `$USER`, use `~/.ssh/config` to specify the ssh connection details such as username, port, or key file used to access the specific host.

As an example, to access host `65.21.20.242` with a specific username and key, you would add the following to `~/.ssh/config`:

```
❯ cat ~/.ssh/config
Host 65.21.20.242
    HostName 65.21.20.242
    User my_remote_user_name
    IdentityFile /path/to/my/private_key
```

Since `task.py` internally uses ssh when accessing hosts, the above example configuration would be applied when accessing the `hetzarm` alias.

## install

The `install` task installs the given alias configuration on the target host with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). It will automatically partition and re-format the host hard drive, meaning all data on the target will be completely overwritten with no option to rollback. During installation, it will also decrypt and deploy the host private key from the sops secrets. The intended use of the `install` task is to install NixOS configuration on a non-NixOS host, to repurpose an existing server, or reset all the configuration and data on the existing server.

Note: `ìnstall` task assumes the given NixOS configuration is compatible with the specified host. In the existing Ghaf CI/CD infrastructure you can safely assume this holds true. However, if you plan to apply the NixOS configurations from this repository on a new infrastructure or onboard new hosts, please read the documentation in [adapting-to-new-environments.md](./adapting-to-new-environments.md).

```bash
❯ inv install --alias hetz86-rel-1
Install configuration 'hetz86-rel-1' on host '46.62.194.110'? [y/N] y
...
### Uploading install SSH keys ###
### Gathering machine facts ###
### Switching system into kexec ###
### Formatting hard drive with disko ###
### Uploading the system closure ###
### Copying extra files ###
### Installing NixOS ###
### Waiting for the machine to become reachable again ###
### Done! ###
...
```

## update-sops-files

The `update-sops-files` task updates all sops yaml and json files according to the rules in [`.sops.yaml`](../.sops.yaml). The intended use is to update the secrets after adding new hosts, admins, or secrets:

```bash
inv update-sops-files
```

## install-release

The `install-release` task installs all the hosts in ci-release environment to allow ephemeral release builds.
It runs the `install` task non-interactively on all the release environment hosts (Jenkins controller, nix remote builders), as well as [connects the relevant testagent](https://github.com/tiiuae/ghaf-infra/tree/main/hosts/hetzci#connect-test-agents) to the release Jenkins controller to fully automate the release environment setup.

```bash
❯ inv install-release
...
# Install hetz86-rel-1
# Install hetzarm-rel-1
# Install hetzci-release
# Connect testagent
...
```