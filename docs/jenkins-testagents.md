<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Jenkins testagents

"testagents" are machines located on-prem which house the hardware required for testing.
Each machine is running one jenkins slave service for each test device, effectively acting as a lock.

One controller is capable of utilizing multiple agents, if they are different variants (currently `dev`, `prod` or `release` are the possible variants).
This is configured in the nix config of the testagent with the `services.testagent.variant` attribute.

## Connecting agent to a controller

To connect given testagent to a Jenkins controller, you must first SSH into the testagent.
There you will find two commands in PATH: `connect` and `disconnect`.

For example to connect some agent to the dev controller, run the following:

```sh
connect https://ci-dev.vedenemo.dev
```

An SSH connection from the agent to the controller will be opened, fetching the connection secret.
This secret is then used to launch the jenkins slaves with a websocket connection.

To disconnect the agent, simply run `disconnect` with no arguments.
