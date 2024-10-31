<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Infra
This repository contains NixOS configurations for the [Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure.

## Highlights
This repository defines flakes-based NixOS configurations for the following targets:
- **[ghafhydra](./hosts/ghafhydra/configuration.nix)** - *[Hydra](https://nixos.wiki/wiki/Hydra) with pre-configured jobset for Ghaf*:
    - Hydra: declaratively configured with Ghaf flake jobset, building on localhost.
    - Binary cache: using [nix-serve-ng](https://github.com/aristanetworks/nix-serve-ng) signing packages that [can be verified](https://github.com/tiiuae/ghaf-infra/blob/c528714a310b420592ec6e73666d80288c5d0f12/docs/adapting-to-new-environments.md?plain=1#L231) with public key: `cache.ghafhydra:XQx1U4555ZzfCCQOZAjOKKPTavumCMbRNd3TJt/NzbU=`.
    - Automatic nix store garbage collection: when free disk space in `/nix/store` drops below [threshold value](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/common.nix#L46) automatically remove garbage.
    - Pre-defined users: allow ssh access for a set of users based on ssh public keys.
    - Secrets: uses [sops-nix](https://github.com/Mic92/sops-nix) to manage secrets - secrets, such as hydra admin password and binary cache signing key, are stored encrypted based on host ssh key.
    - Openssh server with pre-defined host ssh key. Server private key is stored encrypted as [sops secret](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/secrets.yaml#L5) and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/tasks.py#L243).

## Usage
**Important**:
The configuration files in this repository declaratively define the system configuration for all hosts in the Ghaf CI/CD infrastructure. That is, all system configurations - including the secrets - are stored and version controlled in this repository, no additional manual configuration is required. Indeed, all the hosts in the infrastructure might be reinstalled without further notice, so do not assume that anything outside the configurations defined in this repository would be available in the hosts. This includes the administrator's home directories: do not keep any important data in your home, since the contents of `/home` will be regularly deleted.

### Pre-requisites
If you still don't have nix package manager on your local host, install it following the package manager installation instructions from https://nixos.org/download.html.

Then, clone this repository:
```bash
$ git clone https://github.com/tiiuae/ghaf-infra.git
$ cd ghaf-infra
```

All example commands in this document are executed from nix-shell in the root path of your local copy of this repository. Run the following commands to start a nix-shell:

```bash
# Start nix-shell
$ nix-shell
```

### Tasks
Inspired by [nix-community infra](https://github.com/nix-community/infra), this project makes use of [pyinvoke](https://www.pyinvoke.org/) to help with deployment [tasks](./tasks.py).

Run the following command to list the available tasks:
```bash
$ invoke --list
Available tasks:

  alias-list          List available targets (i.e. configurations and alias names)
  build-local         Build NixOS configuration `alias` locally.
  deploy              Deploy the configuration for `alias`.
  install             Install `alias` configuration using nixos-anywhere, deploying host private key.
  pre-push            Run 'pre-push' checks: black, pylint, pycodestyle, reuse lint, nix fmt.
  print-keys          Decrypt host private key, print ssh and age public keys for `alias` config.
  reboot              Reboot host identified as `alias`.
  update-sops-files   Update all sops yaml and json files according to .sops.yaml rules.

```

In the following sections, we will explain the intended usage of the most common above deployment tasks.

#### alias-list
The `alias-list` task lists the alias names for ghaf-infra targets. Alias is simply a name given for the combination of nixosConfig and hostname. All ghaf-infra tasks that need to identify a target, accept an alias name as an argument.

```bash
$ invoke alias-list

Current ghaf-infra targets:

╒═══════════════╤═══════════════╤══════════════╕
│ alias         │ nixosconfig   │ hostname     │
╞═══════════════╪═══════════════╪══════════════╡
│ ghafhydra-dev │ ghafhydra     │ 51.12.56.79  │
╘═══════════════╧═══════════════╧══════════════╛
```

In case `hostname` is not directly accessible for your current `$USER`, use `~/.ssh/config` to specify the ssh connection details such as username, port, or key file used to access the specific host.

As an example, to access host `51.12.56.79` with a specific username and key, you would add the following to `~/.ssh/config`:

```
$ cat ~/.ssh/config
Host 51.12.56.79
    HostName 51.12.56.79
    User my_remote_user_name
    IdentityFile /path/to/my/private_key
```

Since `task.py` internally uses ssh when accessing hosts, the above example configuration would be applied when accessing the `ghafhydra-dev` alias.

#### build-local
The `build-local` task builds the given alias configuration locally. If the alias name is not specified `build-local` builds all alias configurations:

```bash
$ invoke build-local
INFO     Running: nixos-rebuild build --option accept-flake-config true  -v --flake .#ghafhydra
...
building '/nix/store/m0z520c0rpz1qjjw391srjw50426626z-etc.drv'...
building '/nix/store/7jx57i82zmkcjsimb761vqsdcx2sc8yq-nixos-system-ghafhydra-23.05.20231021.5550a85.drv'...
```

#### pre-push
The `pre-push` task runs a set of checks for the contents of this repository. The checks include: python linters, license compliance checks, formatting checks for nix and terraform files and nix flake check for the ghaf-infra flake. The `pre-push` task also locally builds all the alias configurations:

```bash
$ invoke pre-push
INFO     Running: find . -type f -name *.py ! -path *result* ! -path *eggs*
INFO     Running: black -q ./tasks.py
INFO     Running: pylint --disable duplicate-code -rn ./tasks.py
INFO     Running: pycodestyle --max-line-length=90 ./tasks.py
INFO     Running: reuse lint
INFO     Running: terraform fmt -check -recursive
INFO     Running: nix fmt
INFO     Running: nix flake check -v
...
INFO     All pre-push checks passed
```

#### install
The `install` task installs the given alias configuration on the target host with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). It will automatically partition and re-format the host hard drive, meaning all data on the target will be completely overwritten with no option to rollback. During installation, it will also decrypt and deploy the host private key from the sops secrets. The intended use of the `install` task is to install NixOS configuration on a non-NixOS host, or to repurpose an existing server.

Note: `ìnstall` task assumes the given NixOS configuration is compatible with the specified host. In the existing Ghaf CI/CD infrastructure you can safely assume this holds true. However, if you plan to apply the NixOS configurations from this repository on a new infrastructure or onboard new hosts, please read the documentation in [adapting-to-new-environments.md](./docs/adapting-to-new-environments.md).

```bash
$ invoke install --alias ghafhydra-dev
Install configuration 'ghafhydra' on host '51.12.50.33'? [y/N] y
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

#### deploy
The `deploy` task deploys the given alias configuration to the target host with [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild) `switch` subcommand. This task assumes the target host is already running NixOS, and fails if it's not.

Note: unlike the changes made with `install` task, `deploy` changes can be [reverted](https://zero-to-nix.com/concepts/nixos#rollbacks) with `nixos-rebuild switch --rollback` or similar.

```bash
$ invoke deploy --alias ghafhydra-dev
[51.12.50.33] $ nix flake archive --to ssh://51.12.50.33 --json
[51.12.50.33] copying path '/nix/store/dbppismymjc6382g4v6d6sb99pjby37b-source' from 'https://cache.vedenemo.dev'...
[51.12.50.33] copying path '/nix/store/r2ip1850igy8kciyaagw502s3c6ph1s4-source' to 'ssh://51.12.50.33'...
[51.12.50.33] copying path '/nix/store/yj1wxm9hh8610iyzqnz75kvs6xl8j3my-source' to 'ssh://51.12.50.33'...
[51.12.50.33] $ sudo nixos-rebuild switch --option accept-flake-config true --flake /nix/store/1y4kqqi8xbw4ic96ahhhjgl61p61lvdg-source#ghafhydra
...
```

# alternative

## Deploy by using deploy-rs

[follow instructions](./docs/deploy-rs.md)

#### update-sops-files
The `update-sops-files` task updates all sops yaml and json files according to the rules in [`.sops.yaml`](.sops.yaml). The intended use is to update the secrets after adding new hosts, admins, or secrets:

```bash
$ invoke update-sops-files
2023/10/23 08:37:34 Syncing keys for file ghaf-infra/hosts/ghafhydra/secrets.yaml
2023/10/23 08:37:34 File ghaf-infra/hosts/ghafhydra/secrets.yaml already up to date
```

### Updating target hosts
First, update the flake:

```bash
$ nix flake update
...
• Updated input 'nixpkgs':
    'github:nixos/nixpkgs/898cb2064b6e98b8c5499f37e81adbdf2925f7c5' (2023-10-13)
  → 'github:nixos/nixpkgs/5550a85a087c04ddcace7f892b0bdc9d8bb080c8' (2023-10-21)
...
```

Then, deploy the updated configuration to the target host(s):
```bash
$ invoke deploy --alias ghafhydra-dev
```

Notice: be sure to manually verify the target services work as expected after the update. Also, make sure the `install` task still works after the flake update by running the `invoke install alias-name-here` against a test (dev) configuration.

### Onboarding new admins
Onboarding new admins requires the following manual steps:
- Add their user and ssh key to [users](./users/) and [import the user](https://github.com/tiiuae/ghaf-infra/blob/b740f96bcd28e4821f701f6556f4ef2914c7fdf5/hosts/ghafhydra/configuration.nix#L26) on the hosts they need access to.
- Add their [age key](./docs/adapting-to-new-environments.md#add-your-admin-sops-key) to [.sops.yaml](.sops.yaml), update the `creation_rules`, and run the [`update-sops-files`](./README.md#update-sops-files) task.
- [Deploy](./README.md#deploy) the new configuration to changed hosts.

## Secrets
For deployment secrets (such as the binary cache signing key), this project uses [sops-nix](https://github.com/Mic92/sops-nix).

The general idea is: each host have `secrets.yaml` file that contains the encrypted secrets required by that host. As an example, the `secrets.yaml` file for the host ghafhydra defines a secret [`cache-sig-key`](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/secrets.yaml#L2) which is used by the host ghafhydra in [its](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/hosts/ghafhydra/configuration.nix#L15) binary cache [configuration](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/services/binarycache/binary-cache.nix#L12) to sign packages in the nix binary cache. All secrets in `secrets.yaml` can be decrypted with each host's ssh key - sops automatically decrypts the host secrets when the system activates (i.e. on boot or whenever nixos-rebuild switch occurs) and places the decrypted secrets in the configured file paths. An [admin user](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/.sops.yaml#L6) manages the secrets by using the `sops` command line tool.

Each host's private ssh key is stored as sops secret and automatically deployed on [host installation](https://github.com/tiiuae/ghaf-infra/blob/4624f751e38f0d3dfd0fee37e1a4bdfdcf6308be/tasks.py#L243).

`secrets.yaml` files are created and edited with the `sops` utility. The [`.sops.yaml`](.sops.yaml) file tells sops what secrets get encrypted with what keys.

The secrets configuration and the usage of `sops` is adopted from [nix-community infra](https://github.com/nix-community/infra) project.

## Git commit hook

When contributing to this repo you should take the git commit hook into use.

This hook will check the commit message for most trivial mistakes against [current Ghaf commit message guidelines](https://github.com/tiiuae/ghaf/blob/main/CONTRIBUTING.md#commit-message-guidelines)

### Installing git hooks

Just run ``./githooks/install-git-hooks.sh`` in repository main directory, and you should be good to go. Commit message checking script will then run when you commit something.

If you have branches before the git hooks were committed to the repo, you'll have to either rebase them on top of main branch or cherry pick the git hooks commit into your branch.

Also note that any existing commit messages in any branch won't be checked, only new commit messages will be checked.

If you encounter any issues with the git commit message hook, please report them. And while waiting for a fix, you may remove the hook by running ``rm -f .git/hooks/commit-msg`` in the main directory of the repository.

## License
This repository follows the Ghaf team licensing:

| License Full Name | SPDX Short Identifier | Description
| --- | --- | ---
| Apache License 2.0 | [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html) | Source code
| Creative Commons Attribution Share Alike 4.0 International | [CC-BY-SA-4.0](https://spdx.org/licenses/CC-BY-SA-4.0.html) | Documentation
| MIT License | [MIT](https://spdx.org/licenses/MIT.html) | Source code copied from nix community projects

See `./LICENSES/` for the full license text.
