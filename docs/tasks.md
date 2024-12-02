<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tasks

Originally inspired by [nix-community infra](https://github.com/nix-community/infra) this project makes use of [pyinvoke](https://www.pyinvoke.org/) to help with deployment [tasks](../tasks.py).

Run the following command to list the available tasks:
```bash
❯ invoke --list
Available tasks:

  alias-list          List available targets (i.e. configurations and alias names)
  build-local         Build NixOS configuration `alias` locally.
  deploy              Deploy the configuration for `alias`.
  install             Install `alias` configuration using nixos-anywhere, deploying host private key.
  pre-push            Run 'pre-push' checks.
  print-keys          Decrypt host private key, print ssh and age public keys for `alias` config.
  reboot              Reboot host identified as `alias`.
  update-sops-files   Update all sops yaml and json files according to .sops.yaml rules.

```

In the following sections, we will explain the intended usage of the most common of the above deployment tasks.

## alias-list
The `alias-list` task lists the alias names for ghaf-infra targets. Alias is simply a name given for the combination of nixosConfig and hostname. All ghaf-infra tasks that need to identify a target, accept an alias name as an argument.

```bash
❯ invoke alias-list

Current ghaf-infra targets:

╒════════════════════╤═══════════════════╤════════════════╕
│ alias              │ nixosconfig       │ hostname       │
╞════════════════════╪═══════════════════╪════════════════╡
│ binarycache-ficolo │ binarycache       │ 172.18.20.109  │
│ monitoring-ficolo  │ monitoring        │ 172.18.20.108  │
│ build3-ficolo      │ build3            │ 172.18.20.104  │
│ build4-ficolo      │ build4            │ 172.18.20.105  │
│ himalia            │ himalia           │ 172.18.20.106  │
│ testagent-dev      │ testagent-dev     │ 172.18.16.33   │
│ testagent-prod     │ testagent-prod    │ 172.18.16.60   │
│ testagent-release  │ testagent-release │ 172.18.16.32   │
│ hetzarm            │ hetzarm           │ 65.21.20.242   │
│ ghaf-log           │ ghaf-log          │ 95.217.177.197 │
│ ghaf-coverity      │ ghaf-coverity     │ 135.181.103.32 │
│ ghaf-proxy         │ ghaf-proxy        │ 95.216.200.85  │
│ ghaf-webserver     │ ghaf-webserver    │ 37.27.204.82   │
╘════════════════════╧═══════════════════╧════════════════╛

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

## build-local
The `build-local` task builds the given alias configuration locally. If the alias name is not specified `build-local` builds all alias configurations:

```bash
❯ invoke build-local --alias ghaf-log
INFO     Running: nixos-rebuild build --option accept-flake-config true  -v --flake .#ghaf-log
building the system configuration...
Building in flake mode.
...
building '/nix/store/y2m2f5ad5xh6z6z1r31591sgzdl84mcr-etc.drv'...
building '/nix/store/wks2pw9692flrfaqdpv1m0pwfyn17ggj-nixos-system-ghaf-log-24.05.20240830.6e99f2a.drv'...
```

## install
The `install` task installs the given alias configuration on the target host with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). It will automatically partition and re-format the host hard drive, meaning all data on the target will be completely overwritten with no option to rollback. During installation, it will also decrypt and deploy the host private key from the sops secrets. The intended use of the `install` task is to install NixOS configuration on a non-NixOS host, or to repurpose an existing server.

Note: `ìnstall` task assumes the given NixOS configuration is compatible with the specified host. In the existing Ghaf CI/CD infrastructure you can safely assume this holds true. However, if you plan to apply the NixOS configurations from this repository on a new infrastructure or onboard new hosts, please read the documentation in [adapting-to-new-environments.md](./adapting-to-new-environments.md).

```bash
❯ invoke install --alias ghaf-webserver
Install configuration 'ghaf-webserver' on host '37.27.204.82'? [y/N] y
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

## deploy
Note: it's strongly recommended to use the [deploy-rs](https://github.com/tiiuae/ghaf-infra/blob/main/docs/deploy-rs.md) instead of the `deploy` task.

The `deploy` task deploys the given alias configuration to the target host with [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild) `switch` subcommand. This task assumes the target host is already running NixOS, and fails if it's not.

Note: unlike the changes made with `install` task, `deploy` changes can be [reverted](https://zero-to-nix.com/concepts/nixos#rollbacks) with `nixos-rebuild switch --rollback` or similar.

```bash
❯ invoke deploy --alias ghaf-webserver
...
```

## update-sops-files
The `update-sops-files` task updates all sops yaml and json files according to the rules in [`.sops.yaml`](../.sops.yaml). The intended use is to update the secrets after adding new hosts, admins, or secrets:

```bash
$ invoke update-sops-files
```
