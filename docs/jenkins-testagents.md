<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Jenkins testagents

"testagents" are machines located on-prem which house the hardware required for testing.
Each machine is running one jenkins slave service for each test device, effectively acting as a lock.

One controller is capable of utilizing multiple agents, if they are different variants (currently `dbg`, `dev`, `prod` and `release` are the possible variants).
This is configured in the nix config of the testagent with the `services.testagent.variant` attribute.

## Agent tooling

Each testagent has the following tools available to the Jenkins agent services
(configured in `hosts/testagent/agent.nix` and `hosts/testagent/agents-common.nix`):

- **[BrainStem](https://acroname.com/software/brainstem-development-kit)**
  (`AcronameHubCLI`): controls Acroname programmable USB hubs for
  power-cycling and USB switching of test devices. Packaged in `pkgs/brainstem/`
  with udev rules for device access.
- **`policy-checker`**: a Go tool (in `pkgs/policy-checker/`) that wraps
  `verify-signature` to validate SLSA provenance and image signatures against
  the certificates in `ghaf-infra-pki` before flashing.
- **`ghaf-robot`**: [Robot Framework](https://robotframework.org/) test runner
  from the `robot-framework` flake input.
- **[FleetDM](https://fleetdm.com/) credentials**: agents hold Fleet enrollment
  secrets and API tokens (via sops) so that Ghaf images flashed during CI
  testing can register with the `ghaf-fleetdm` server. Fleet manages the
  Ghaf end-devices, not the test agents themselves.

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

To set up a new testagent:

1. Rack the machine, connect test devices, and ensure network access.
2. Follow the [adding a host](./adding-a-host.md) runbook to create the NixOS
   configuration, install the host, and set up secrets. Use an existing testagent
   as the configuration reference instead of the Hetzner Cloud example.
3. For a Tampere agent, follow the
   [Nebula onboarding checklist](./nebula.md#onboarding-checklist) with the
   `testagent,office` groups. The existing UAE test agents do not use Nebula;
   follow their site configuration under `hosts/uae/testagent/` instead.
4. SSH into the testagent and run `connect` with the target controller URL.
