<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
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

## print-revision

The `print-revision` task prints currently deployed ghaf-infra git revision for the given `alias` host:

```bash
❯ inv print-revision --alias=hetzarm
...

Currently deployed revision(s):

╒═════════╤══════════════════════════════════════════╤═════════════════╤══════════════════════════════════╕
│ alias   │ revision                                 │ revision date   │ revision subject                 │
╞═════════╪══════════════════════════════════════════╪═════════════════╪══════════════════════════════════╡
│ hetzarm │ 34415d537396d2ec39d4403a9a8f48150cf1ee40 │ 2025-09-18      │ Remove older profile generations │
╘═════════╧══════════════════════════════════════════╧═════════════════╧══════════════════════════════════╛
```

The output table includes the following details:
- `alias`: Target ghaf-infra host `alias` name
- `revision`: Ghaf-infra git commit revision currently deployed on the target host. This detail is read from the remote host with command `nixos-version --configuration-revision`. On [OSC 8 compatible](https://github.com/Alhadis/OSC8-Adoption/) terminals, `revision` is a hyperlink to ghaf-infra github
- `revision date`: Git log [committer date](https://git-scm.com/docs/git-log#Documentation/git-log.txt-cs) in short format
- `revision subject`: Git log [commit subject](https://git-scm.com/docs/git-log#Documentation/git-log.txt-s)

If `alias` is not specified, `print-revision` lists the deployed git revisions for all ghaf-infra hosts sorted by the git revision date:

```bash
❯ inv print-revision
...

Currently deployed revision(s):

╒═══════════════════╤════════════════════════════════════════════════╤═════════════════╤═══════════════════════════════════════════════════════════╕
│ alias             │ revision                                       │ revision date   │ revision subject                                          │
╞═══════════════════╪════════════════════════════════════════════════╪═════════════════╪═══════════════════════════════════════════════════════════╡
│ hetz86-rel-1      │ 86a1b0c2148e63ff2f01ea9d69b50b8710240b68       │ 2025-10-06      │ Increase retry timeout on provenance failure              │
│ hetzarm-rel-1     │ 86a1b0c2148e63ff2f01ea9d69b50b8710240b68       │ 2025-10-06      │ Increase retry timeout on provenance failure              │
│ hetzci-prod       │ 86a1b0c2148e63ff2f01ea9d69b50b8710240b68       │ 2025-10-06      │ Increase retry timeout on provenance failure              │
│ hetzci-release    │ 86a1b0c2148e63ff2f01ea9d69b50b8710240b68       │ 2025-10-06      │ Increase retry timeout on provenance failure              │
│ ghaf-log          │ 0162221a15159e6053db6b85697ff2e91865f8e5       │ 2025-09-22      │ Start using zramswap module on hosts that enable zramSwap │
│ ghaf-proxy        │ 0162221a15159e6053db6b85697ff2e91865f8e5       │ 2025-09-22      │ Start using zramswap module on hosts that enable zramSwap │
│ ghaf-webserver    │ 0162221a15159e6053db6b85697ff2e91865f8e5       │ 2025-09-22      │ Start using zramswap module on hosts that enable zramSwap │
│ hetz86-1          │ 34415d537396d2ec39d4403a9a8f48150cf1ee40       │ 2025-09-18      │ Remove older profile generations                          │
│ hetzarm           │ 34415d537396d2ec39d4403a9a8f48150cf1ee40       │ 2025-09-18      │ Remove older profile generations                          │
│ hetz86-builder    │ f92334fe58d657712627bd317349920251c50785       │ 2025-08-07      │ developers: Add Gayathri                                  │
│ ghaf-auth         │ 5e579ac4eae173ad3e36ea5267a6b9f2a19729b1       │                 │                                                           │
│ ghaf-lighthouse   │ 268bc910409fd8579747a78526ec8ffac4bb3813-dirty │                 │                                                           │
│ ghaf-monitoring   │ 86a1b0c2148e63ff2f01ea9d69b50b8710240b68-dirty │                 │                                                           │
│ hetzci-dev        │ d7ae303867280371259f018bf4e0f5ed13f73552-dirty │                 │                                                           │
│ nethsm-gateway    │ d7ae303867280371259f018bf4e0f5ed13f73552-dirty │                 │                                                           │
│ testagent-dev     │ 45b4da02c49f23f5619590d286252a5de28a34e4-dirty │                 │                                                           │
│ testagent-prod    │ 9066891fe09531a6cea9aadb3412bca595c93fe4       │                 │                                                           │
│ testagent-release │ 05335d38fc73964286cc5faca486f5b1f9b7953e-dirty │                 │                                                           │
│ testagent-uae-dev │ (unknown)                                      │                 │                                                           │
│ testagent2-prod   │ fa149ab5230c099e6f1813ea966b19ca66dc1ec6-dirty │                 │                                                           │
╘═══════════════════╧════════════════════════════════════════════════╧═════════════════╧═══════════════════════════════════════════════════════════╛
```

Revision '`(unknown)`' indicates running `nixos-version --configuration-revision` on the remote host failed.
This may happen, for instance, if you don't have access to the given host on the current network.
