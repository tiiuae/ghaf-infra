<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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

This is a fast local inventory command: it evaluates target metadata and does not contact the remote hosts. Use it when you need the `nixosconfig` name or want to discover aliases before install, build, or deployment work. Use `print-revision` when you need the current remote deployment state.

```bash
❯ inv alias-list

Current ghaf-infra targets:

╒═══════════════════════╤═══════════════════════╤═════════════════╕
│ alias                 │ nixosconfig           │ hostname        │
╞═══════════════════════╪═══════════════════════╪═════════════════╡
│ ghaf-auth             │ ghaf-auth             │ 37.27.190.109   │
│ ghaf-fleetdm          │ ghaf-fleetdm          │ 95.216.169.87   │
│ ghaf-lighthouse       │ ghaf-lighthouse       │ 65.109.141.136  │
│ ghaf-log              │ ghaf-log              │ 95.217.177.197  │
│ ghaf-monitoring       │ ghaf-monitoring       │ 135.181.103.32  │
│ ghaf-registry         │ ghaf-registry         │ 89.167.65.27    │
│ ghaf-webserver        │ ghaf-webserver        │ 37.27.204.82    │
│ hetz86-1              │ hetz86-1              │ 37.27.170.242   │
│ hetz86-builder        │ hetz86-builder        │ 65.108.7.79     │
│ hetz86-dbg-1          │ hetz86-dbg-1          │ 46.62.194.110   │
│ hetz86-rel-2          │ hetz86-rel-2          │ 65.21.200.168   │
│ hetzarm               │ hetzarm               │ 65.21.20.242    │
│ hetzarm-dbg-1         │ hetzarm-dbg-1         │ 46.62.194.107   │
│ hetzarm-rel-1         │ hetzarm-rel-1         │ 46.62.196.166   │
│ hetzci-dbg            │ hetzci-dbg            │ 95.216.200.85   │
│ hetzci-dev            │ hetzci-dev            │ 157.180.119.138 │
│ hetzci-prod           │ hetzci-prod           │ 157.180.43.236  │
│ hetzci-release        │ hetzci-release        │ 95.217.210.252  │
│ nethsm-gateway        │ nethsm-gateway        │ 192.168.70.11   │
│ testagent-dbg         │ testagent-dbg         │ 172.18.16.26    │
│ testagent-dev         │ testagent-dev         │ 172.18.16.33    │
│ testagent-prod        │ testagent-prod        │ 172.18.16.60    │
│ testagent-release     │ testagent-release     │ 172.18.16.32    │
│ testagent2-prod       │ testagent2-prod       │ 172.18.16.25    │
│ uae-azureci-az86-1    │ uae-azureci-az86-1    │ 20.46.48.30     │
│ uae-azureci-dev       │ uae-azureci-dev       │ 20.174.185.164  │
│ uae-azureci-hetzarm-1 │ uae-azureci-hetzarm-1 │ 91.98.90.243    │
│ uae-azureci-prod      │ uae-azureci-prod      │ 74.162.68.205   │
│ uae-azureci-registry  │ uae-azureci-registry  │ 40.120.125.69   │
│ uae-lab-node1         │ uae-lab-node1         │ 172.31.107.42   │
│ uae-nethsm-gateway    │ uae-nethsm-gateway    │ 172.31.141.51   │
│ uae-testagent-prod    │ uae-testagent-prod    │ 172.20.16.24    │
│ uae-testagent2-prod   │ uae-testagent2-prod   │ 172.20.16.25    │
╘═══════════════════════╧═══════════════════════╧═════════════════╛

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

Note: `install` task assumes the given NixOS configuration is compatible with the specified host. In the existing Ghaf CI/CD infrastructure you can safely assume this holds true.

```bash
❯ inv install --alias hetz86-rel-2
Install configuration 'hetz86-rel-2'? [y/N] y
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
# Install hetz86-rel-2
# Install hetzarm-rel-1
# Install hetzci-release
# Connect testagent
...
```

## reboot

The `reboot` task reboots the host identified by the given alias. It triggers a reboot, waits for the host to go down, and then waits for it to come back up:

```bash
❯ inv reboot --alias hetzarm
```

## print-keys

The `print-keys` task decrypts the host's private SSH key from sops secrets and prints the corresponding SSH and age public keys. This is useful when adding a new host to `.sops.yaml` after the initial install:

```bash
❯ inv print-keys --alias ghaf-example
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
age1abc123...
```

## print-revision

The `print-revision` task probes the remote host and prints the currently deployed ghaf-infra git revision for the given `alias` host:

```bash
❯ inv print-revision --alias=hetzarm
...

Currently deployed revision(s):

╒═════════╤══════════════╤════════════════╤══════════════════╤════════════╤══════════════════════════════════════╕
│ alias   │ hostname     │ needs reboot   │ revision (rev)   │ rev date   │ rev subject                          │
╞═════════╪══════════════╪════════════════╪══════════════════╪════════════╪══════════════════════════════════════╡
│ hetzarm │ 65.21.20.242 │ no             │ 4966d195a6a1     │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
╘═════════╧══════════════╧════════════════╧══════════════════╧════════════╧══════════════════════════════════════╛
```

The output table includes the following details:
- `alias`: Target ghaf-infra host `alias` name
- `hostname`: Target host address, matching the `hostname` column in `inv alias-list`
- `needs reboot`: Whether booted `initrd`, `kernel`, or `kernel-modules` differ from the current system closure. `yes` means rebooting is required to activate the current boot artifacts, `no` means they match, and `(unknown)` means the remote probe failed
- `revision (rev)`: Ghaf-infra git commit revision currently deployed on the target host. This detail is read from the remote host with command `nixos-version --configuration-revision`. The table shows a short revision prefix, keeping `-dirty` when the deployed system was built from a dirty tree. On [OSC 8 compatible](https://github.com/Alhadis/OSC8-Adoption/) terminals, clean revisions are hyperlinks to the full ghaf-infra github commit
- `rev date`: Git log [committer date](https://git-scm.com/docs/git-log#Documentation/git-log.txt-cs) in short format
- `rev subject`: Git log [commit subject](https://git-scm.com/docs/git-log#Documentation/git-log.txt-s)

If `alias` is not specified, `print-revision` lists the deployed git revisions for all ghaf-infra hosts sorted by the git revision date:

```bash
❯ inv print-revision
...

Currently deployed revision(s):

╒══════════════════╤═══════════════╤════════════════╤════════════════════╤════════════╤══════════════════════════════════════╕
│ alias            │ hostname      │ needs reboot   │ revision (rev)     │ rev date   │ rev subject                          │
╞══════════════════╪═══════════════╪════════════════╪════════════════════╪════════════╪══════════════════════════════════════╡
│ ghaf-auth        │ 37.27.190.109 │ no             │ 4966d195a6a1       │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
│ hetzci-dbg       │ 95.216.200.85 │ no             │ bccecd160df0-dirty │            │                                      │
│ uae-azureci-prod │ 74.162.68.205 │ yes            │ 4966d195a6a1       │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
│ testagent-dbg    │ 172.18.16.26  │ (unknown)      │ (unknown)          │            │                                      │
╘══════════════════╧═══════════════╧════════════════╧════════════════════╧════════════╧══════════════════════════════════════╛
```

Revision or needs-reboot value '`(unknown)`' indicates running the remote probe failed.
This may happen, for instance, if you don't have access to the given host on the current network.
