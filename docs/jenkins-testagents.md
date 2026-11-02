<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Jenkins testagents

"testagents" are machines located on-prem which house the hardware required for testing.
Each machine is running one jenkins slave service for each test device, effectively acting as a lock.

Each testagent sets its variant (`dbg`, `dev`, `prod` or `release`) in `services.testagent.variant`
and lists its devices in `services.testagent.devices`.
Controller registrations in `services.ghaf-jenkins.agents` read each agent's
variant, devices and node prefix from its host configuration
(see [`hosts/hetzci/common.nix`](../hosts/hetzci/common.nix)). Existing node names
remain `<variant>-<device>`. Interchangeable physical agents can share these
nodes when connected to different controllers or swapped between controllers.
To run overlapping device labels simultaneously on one controller, configure
distinct `nodeNamePrefix` values in the agent and its controller registration.

## Standalone consumers

Use the [consumer interface](./jenkins-consumers.md) for free-form test configuration,
SOPS secrets, optional hardware tools, and controller registrations.
Agents still use mutable `connect` / `disconnect` commands and can move between
controllers without rebuilding their NixOS configuration.

## Agent tooling

Each testagent has the following tools available to the Jenkins agent services
(configured in the [`testagent` module](../modules/testagent/), exported as
`nixosModules.testagent`, with site defaults in `hosts/testagent/finland.nix`
and `hosts/uae/testagent/uae.nix`):

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
Until then, the agents reconnect to the same controller after a reboot, and
after the controller restarts or is reset: an agent that cannot reconnect for
five minutes restarts and fetches the secret again.

## Adding a new hardware device to an existing agent

To add a new test device to a testagent that is already running:

1. In the testagent's `configuration.nix` (under `hosts/testagent/` or
   `hosts/uae/testagent/`), add the device to `services.testagent.devices`,
   its udev rules, and its entry in `services.testagent.testConfig`. Each
   device gets its own Jenkins agent service.
2. Controller registrations automatically read the agent's device list. If
   the device label is new, also:
   - add it to `device_catalog()` in
     `modules/jenkins/pipeline-library/vars/pipelineModel.groovy`; the entry's
     `name` must match the device's key in `test_config.json`
   - add it to the `DEVICE_TAG` choices in
     `modules/jenkins/pipelines/ghaf-hw-test-manual.groovy`

   Otherwise the agent connects, but hardware tests fail with
   `Unknown DEVICE_TAG`.
3. Deploy the controllers that use the agent and the updated agent configuration
   with `deploy .#<testagent-name>`.
4. Connect the agent to the controller (see above).

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
