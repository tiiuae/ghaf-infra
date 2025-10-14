<!--
SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Using deploy-rs

As an alternative to using `tasks.py` and `invoke deploy` commands,
the remote hosts are also defined in `nix/deployments.nix` as [deploy-rs](https://github.com/serokell/deploy-rs) nodes.

This makes deploying multiple hosts easier as it can be done with one command.
`deploy-rs` also has automatic rollback functionality, so the system is rolled back if the configuration fails to activate.

The nix devshell includes the `deploy` binary so enter the shell and you can use the commands.

Run `deploy --help` to see all the options.
Most notably, `-s` to skip the `nix flake check` stage that is ran by default before deploying, `-i` for interactive mode to avoid mistakes,
or `--ssh-user` if your current username does not match your username on the target machine.
If deploying on weak machine, or on a different arch than the target configuration, you might want to additionally use `--remote-build` to build the config on the target.

## Deploying hosts

To deploy a single host, simply use the deploy command with the name of the node:

```sh
deploy .#ghaf-monitoring
```

You can specify a list of hosts to deploy by using the `--targets` option:

```sh
deploy --targets .#ghaf-monitoring .#hetzarm
```

Example assuming the checks have passed beforehand, and using different username for ssh:

```sh
deploy -si --ssh-user myuser .#ghaf-monitoring
```

Running just `deploy` without any arguments will deploy every host defined in the configuration, even if they have no changes. This is usually not something you want to do.
