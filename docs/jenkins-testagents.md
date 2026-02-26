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

## Adding a new hardware device to an existing agent

To add a new test device to a testagent that is already running:

1. Add the device entry to the testagent's NixOS configuration (under
   `hosts/testagent/<variant>/configuration.nix`). Each device gets its own
   Jenkins agent service.
2. Deploy the updated configuration with `deploy .#<testagent-name>`.
3. Connect the agent to the controller (see above).

## Adding a new test agent

To set up a brand new testagent machine from scratch:

1. **Provision the hardware** — rack the machine, connect test devices, and
   ensure network access.
2. **Add the host to ghaf-infra** — follow the
   [adding a host](./adding-a-host.md) runbook to create the NixOS
   configuration, secrets, and deployment entries.
3. **Enroll in Nebula** — testagents need Nebula connectivity to reach the
   Jenkins controllers. Follow the
   [Nebula onboarding checklist](./nebula.md#onboarding-checklist), assigning
   the `testagent` group (and `office` or `uae-lab` as appropriate).
4. **Install** — provision the machine with `inv install --alias <name>`
   (see [tasks](./tasks.md#install)).
5. **Connect to controller** — SSH into the testagent and run `connect`
   with the target controller URL.
