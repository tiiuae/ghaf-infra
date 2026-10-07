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
  install-release     Deploy and reset release hosts; reinstall only for disk layout changes.
  print-keys          Decrypt host private key, print ssh and age public keys for `alias` config.
  print-revision      Print the deployed git revision, reboot state and kernels on the 'alias' host.
  reboot              Reboot host identified as `alias`, selected aliases, or hosts needing reboot.
  renew-nebula-certificates
                      Renew Nebula host certificates and keys stored in sops.
  update-sops-files   Update all sops files according to .sops.yaml rules.
```

Most tasks are described below. For `renew-nebula-certificates`, see
[Renewing host certificates](./nebula.md#renewing-host-certificates).

## alias-list

The `alias-list` task lists the alias names for ghaf-infra targets. Alias is simply a name given for the combination of nixosConfig and host address. All ghaf-infra tasks that need to identify a target, accept an alias name as an argument.

This is a fast local inventory command: it evaluates target metadata and does not contact the remote hosts. Use it when you need the `nixosconfig` name or want to discover aliases before install, build, or deployment work. Use `print-revision` when you need the current remote deployment state.

```bash
❯ inv alias-list

Current ghaf-infra targets:

╒═══════════════════════╤═══════════════════════╤═════════════════╕
│ alias                 │ nixosconfig           │ host address    │
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
│ nethsm-gateway-dev    │ nethsm-gateway-dev    │ 192.168.70.2    │
│ testagent-dbg         │ testagent-dbg         │ 172.18.16.26    │
│ testagent-dev         │ testagent-dev         │ 172.18.16.33    │
│ testagent-prod        │ testagent-prod        │ 172.18.16.60    │
│ testagent-release     │ testagent-release     │ 172.18.16.32    │
│ testagent2-prod       │ testagent2-prod       │ 172.18.16.25    │
│ uae-azureci-az86-1    │ uae-azureci-az86-1    │ 20.46.48.30     │
│ uae-azureci-hetzarm-1 │ uae-azureci-hetzarm-1 │ 91.98.90.243    │
│ uae-azureci-prod      │ uae-azureci-prod      │ 74.162.68.205   │
│ uae-azureci-registry  │ uae-azureci-registry  │ 74.162.68.150   │
│ uae-lab-node1         │ uae-lab-node1         │ 172.31.107.42   │
│ uae-nethsm-gateway    │ uae-nethsm-gateway    │ 172.31.141.51   │
│ uae-testagent-prod    │ uae-testagent-prod    │ 172.20.16.24    │
│ uae-testagent2-prod   │ uae-testagent2-prod   │ 172.20.16.26    │
╘═══════════════════════╧═══════════════════════╧═════════════════╛

```

In case the host address is not directly accessible for your current `$USER`, use `~/.ssh/config` to specify the ssh connection details such as username, port, or key file used to access the specific host.

As an example, to access host `65.21.20.242` with a specific username and key, you would add the following to `~/.ssh/config`:

```
❯ cat ~/.ssh/config
Host 65.21.20.242
    HostName 65.21.20.242
    User my_remote_user_name
    IdentityFile /path/to/my/private_key
```

Since `tasks.py` internally uses ssh when accessing hosts, the above example configuration would be applied when accessing the `hetzarm` alias.

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

The `update-sops-files` task runs `sops updatekeys` on every file matched by
a `path_regex` rule in [`.sops.yaml`](../.sops.yaml), including YAML, JSON,
and encrypted `.crypt` files. Run it after changing host or admin keys, or
the rules that determine who can decrypt each file:

```bash
inv update-sops-files
```

## install-release

The `install-release` task deploys the current checkout to the ci-release
Jenkins controller, its two builders, and its test agent; resets the controller
and builders to that baseline in parallel; and starts a fresh credential epoch.

Use `inv install-release` for the normal release flow. It deploys and resets the
existing hosts without repartitioning them. Use `--reinstall` only for initial
provisioning or when a disk layout change requires reinstalling the three
release hosts; it is not part of a normal release.

```bash
❯ inv install-release              # deploy and reset (normal release)
❯ inv install-release --no-deploy  # reset the deployed systems only
❯ inv install-release --reinstall  # disk layout change: erase and reinstall
```

See [baseline reset updates](./baseline-reset.md#updates) for when to use each
mode and the checks it performs.

## reboot

The `reboot` task reboots the host identified by the given alias. It triggers a reboot, waits for the host to go down, and then waits for it to come back up:

```bash
❯ inv reboot hetzarm
```

You can also pass one or more explicit aliases through `--aliases`. Multiple aliases are comma-separated:

```bash
❯ inv reboot --aliases hetzci-dbg
❯ inv reboot --aliases hetzci-dbg,hetzci-dev
```

It can also reboot every host where the booted kernel, initrd, or kernel modules differ from the persistent system profile selected for the next boot:

```bash
❯ inv reboot --needs-reboot
```

The `--needs-reboot` mode excludes the release hosts (`hetz86-rel-2`, `hetzarm-rel-1` and `hetzci-release`) and logs that they were skipped. Use `inv install-release` for their boot selection, baseline verification and credential provisioning. The remaining targets are probed; hosts with `no` or `(unknown)` reboot state are skipped, and matching hosts are rebooted sequentially after confirmation. Explicit `--aliases` mode asks for confirmation when more than one host is listed. Without `--yes`, answer `y` to continue; any other answer cancels before rebooting hosts. Use `--yes` to skip these confirmation prompts.

If a host was deliberately booted into an older generation, its persistent profile can still select the newer generation. That host may report `needs reboot: yes`, and `--needs-reboot` can reboot it into the newer generation. Use `--aliases` to reboot other hosts without including the host running the older generation.

The output looks like this, with timestamps and hosts depending on the current fleet state:

```text
❯ inv reboot --needs-reboot
2026-08-12 10:15:00 | INFO     | Skipping release hosts in --needs-reboot: hetz86-rel-2, hetzarm-rel-1, hetzci-release; use 'inv install-release'
2026-08-12 10:15:00 | INFO     | Probing 30 host(s) (up to 5s each)
Reboot 1 host(s) needing reboot: uae-azureci-prod? [y/N] y
2026-08-12 10:16:01 | INFO     | [uae-azureci-prod] reboot: waiting for 74.162.68.205 to shut down
2026-08-12 10:16:19 | INFO     | [uae-azureci-prod] reboot: waiting for 74.162.68.205 to start
2026-08-12 10:16:58 | INFO     | [uae-azureci-prod] reboot: host is back up
2026-08-12 10:16:58 | INFO     | Rebooted 1 host(s) needing reboot
```

With `--yes`, the probe, per-host wait logs, and final summary are the same, but the confirmation prompt is omitted:

```bash
❯ inv reboot --needs-reboot --yes
❯ inv reboot --aliases hetzci-dbg,hetzci-dev --yes
```

The task confirms each reboot by waiting for the host's SSH port to disappear and then become reachable again. For reboot waits, shutdown must happen within 120 seconds and startup within 600 seconds. In single-host mode, a failed reboot command or timeout exits with an error. In multi-host modes, the task logs failed hosts, continues with the remaining selected hosts, and exits with an error summary if any host failed.

## print-keys

The `print-keys` task decrypts the host's private SSH key from sops secrets and prints the corresponding SSH and age public keys. This is useful when adding a new host to `.sops.yaml` after the initial install:

```bash
❯ inv print-keys --alias ghaf-example
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
age1abc123...
```

## print-revision

The `print-revision` task probes the remote host and prints the currently deployed ghaf-infra git revision, reboot state and kernel versions for the given `alias` host:

```bash
❯ inv print-revision --alias=hetzarm
...

Currently deployed revision(s):

╒═════════╤════════════════╤══════════╤═══════════════════╤══════════════════╤════════════╤══════════════════════════════════════╕
│ alias   │ host address   │ needs    │ kernel            │ revision (rev)   │ rev date   │ rev subject                          │
│         │                │ reboot   │                   │                  │            │                                      │
╞═════════╪════════════════╪══════════╪═══════════════════╪══════════════════╪════════════╪══════════════════════════════════════╡
│ hetzarm │ 65.21.20.242   │ yes      │ 6.12.78 → 6.12.79 │ 4966d195a6a1     │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
╘═════════╧════════════════╧══════════╧═══════════════════╧══════════════════╧════════════╧══════════════════════════════════════╛
Kernel: running version; → next boot when different.
```

The output table includes the following details:
- `alias`: Target ghaf-infra host alias name
- `host address`: Target host address, matching the `host address` column in `inv alias-list`
- `needs reboot`: Whether booted `initrd`, `kernel`, or `kernel-modules` differ from the persistent `/nix/var/nix/profiles/system` closure selected for the next boot. `yes` means rebooting is required to activate those boot artifacts, `no` means they match, and `(unknown)` means the comparison could not be read
- `kernel`: Running kernel release from `uname -r`. When the next kernel release differs, the same line shows `running → next`, with the next release read from `/nix/var/nix/profiles/system/kernel-modules/lib/modules/`. A single version means both match. If only the next kernel is unreadable, the running version is followed by `(next: unknown)`. The persistent system profile also reflects deployments staged with `nixos-rebuild boot`. `(unknown)` means that kernel release could not be read
- `revision (rev)`: Ghaf-infra git commit revision of the active system on the target host, read with `nixos-version --configuration-revision`. A deployment staged with `deploy --boot` can show the old active revision alongside a newer next-boot kernel. The table shows a 12-character revision prefix, or an 8-character prefix followed by `-dirty` when the deployed system was built from a dirty tree. On [OSC 8 compatible](https://github.com/Alhadis/OSC8-Adoption/) terminals, clean revisions are hyperlinks to the full ghaf-infra github commit
- `rev date`: Git log [committer date](https://git-scm.com/docs/git-log#Documentation/git-log.txt-cs) in short format
- `rev subject`: Git log [commit subject](https://git-scm.com/docs/git-log#Documentation/git-log.txt-s), truncated to 40 characters to limit table width

Matching kernel versions can still have `needs reboot` set to `yes` if the initrd or module paths changed.

If `alias` is not specified, `print-revision` lists the deployed git revisions for all ghaf-infra hosts sorted by the git revision date:

```bash
❯ inv print-revision
...

Currently deployed revision(s):

╒══════════════════╤════════════════╤═══════════╤═══════════════════╤══════════════════╤════════════╤══════════════════════════════════════╕
│ alias            │ host address   │ needs     │ kernel            │ revision (rev)   │ rev date   │ rev subject                          │
│                  │                │ reboot    │                   │                  │            │                                      │
╞══════════════════╪════════════════╪═══════════╪═══════════════════╪══════════════════╪════════════╪══════════════════════════════════════╡
│ ghaf-auth        │ 37.27.190.109  │ no        │ 6.12.78           │ 4966d195a6a1     │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
│ uae-azureci-prod │ 74.162.68.205  │ yes       │ 6.12.78           │ 4966d195a6a1     │ 2026-08-06 │ hosts/hetzci: update Jenkins plugins │
│ hetzci-dbg       │ 95.216.200.85  │ yes       │ 6.12.78 → 6.12.79 │ bccecd16-dirty   │            │                                      │
│ testagent-dbg    │ 172.18.16.26   │ (unknown) │ (unknown)         │ (unknown)        │            │                                      │
╘══════════════════╧════════════════╧═══════════╧═══════════════════╧══════════════════╧════════════╧══════════════════════════════════════╛
Kernel: running version; → next boot when different.
```

An `(unknown)` value means the corresponding information could not be read. If the remote probe fails entirely, revision, reboot state and both kernel versions are unknown. This may happen, for instance, if you don't have access to the given host on the current network.
