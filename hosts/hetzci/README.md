<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Jenkins CI in Hetzner

This directory contains the configuration for Ghaf Jenkins CI in Hetzner.

## Prerequisites

All commands in this document assume you have completed the [Getting Started](../../README.md#getting-started) steps from the main README and are running inside the `nix develop` shell.

## Directory Structure

```shell
hosts/hetzci/
├── common.nix              # HetzCI-wide Jenkins and host configuration
├── cloud.nix               # Hetzner Cloud configuration
├── remote-builders.nix     # Remote Nix builders used by Jenkins
├── signing.nix             # HetzCI signing configuration
├── dbg
│   └── ...
├── dev
│   └── ...
├── prod
│   └── ...
├── release
│   └── ...
├── vm
│   ├── configuration.nix  # nixosConfiguration for the jenkins host
│   ├── disk-config.nix    # disko nix configuration
│   └── secrets.yaml       # encrypted sops secrets specific to given host
```

The environment-independent Jenkins service implementation, CasC fragments,
plugins, pipelines, and shared library live in [`modules/jenkins/`](../../modules/jenkins/).
It is exported as `nixosModules.jenkins`. Test-agent services and tooling live in
[`modules/testagent/`](../../modules/testagent/) and are exported as
`nixosModules.testagent`.

HetzCI-specific defaults, authentication groups, test-agent nodes, and authorized
keys remain in [`common.nix`](./common.nix). Each environment declares its own
pipelines, integration enablement, and SOPS secrets in its `configuration.nix`.
The Jenkins module accepts secret file paths and does not manage the secret
provider. The test-agent module currently takes a SOPS credentials file through
`services.testagent.credentialsFile`.

Pipeline tests live in [`tests/jenkins/`](../../tests/jenkins/) at the
repository root and run through the `nix fmt` hooks.

### Environments

- **`prod`**: production CI for ghaf development. Web UI: https://ci-prod.vedenemo.dev/
- **`release`**: release CI for ghaf release builds. Web UI: https://ci-release.vedenemo.dev/
- **`dev`**: development CI for ghaf-infra and hw-test development. Web UI: https://ci-dev.vedenemo.dev/
- **`dbg`**: debug CI environment.
- **`vm`**: local QEMU VM for testing changes before deploying. Modified for local use: simplified Caddy config, no Jenkins authentication, auto-login as root.

### Jenkins configuration

All Jenkins controllers configure `services.ghaf-jenkins`. The OCI registry is
part of the build-to-hardware-test artifact flow, so its URL and password file
are required. Authentication and the GitHub, Cachix, Jira, and archive features
are disabled by default and enabled explicitly.

```nix
imports = [ inputs.ghaf-infra.nixosModules.jenkins ];

services.ghaf-jenkins = {
  enable = true;
  envType = "dev";
  url = "https://ci.example.com";

  registry = {
    url = "registry.example.com";
    passwordFile = config.sops.secrets.oci_registry_password.path;
  };

  auth = {
    enable = true;
    domain = "ci.example.com";
    clientID = "jenkins-dev";
    oidcIssuerUrl = "https://auth.example.com";
    clientSecretFile = config.sops.secrets.oauth2_proxy_client_secret.path;
    cookieSecretFile = config.sops.secrets.oauth2_proxy_cookie_secret.path;
    groups."ci-admins" = [ "Overall/Administer" ];
  };

  integrations.github = {
    enable = true;
    tokenFile = config.sops.secrets.jenkins_github_commit_status_token.path;
    webhookSecretFile = config.sops.secrets.jenkins_github_webhook_secret.path;
  };
};
```

Single-secret integrations use the same explicit structure under
`integrations.cachix` and `integrations.jira`. Artifact archiving is configured
under `archive`, with credentials in `archive.s3Credentials`. Consumers provide
the paths from their chosen secret manager; the HetzCI hosts use SOPS.

## Usage

The following sections describe the intended workflow for hetzci development.

### Develop and Test Changes Locally in a VM

The flake app [`run-hetzci-vm`](../../nix/apps.nix) runs the [vm](./vm) configuration locally in a QEMU VM, decrypting sops secrets per [`.sops.yaml`](../../.sops.yaml). The general idea is explained in [tiiuae/ci-vm-example](https://github.com/tiiuae/ci-vm-example?tab=readme-ov-file#secrets).

**Prerequisite:** KVM acceleration (`/dev/kvm` must be available and accessible to your user).

Run the VM:

```bash
❯ nix run .#run-hetzci-vm
```

This starts a headless VM with a console in the current terminal. A disk file (`hetzci-vm.qcow2`) is created in the working directory and removed on exit by default (ephemeral state).

Common options:

```bash
# Keep VM disk across reboots
❯ nix run .#run-hetzci-vm -- --keep-disk

# Use an independent guest Nix store (instead of mounting the host store)
❯ nix run .#run-hetzci-vm -- --no-host-nix-store

# Override VM resources
❯ nix run .#run-hetzci-vm -- --ram-gb 16 --cpus 6 --disk-size 120G
```

**Default behavior** (without `--no-host-nix-store`):
- The guest mounts host `/nix/store` as a read-only backing store.
- Guest-created store paths are written to a separate writable guest layer.
- The guest sees a single `/nix/store` view: writable layer first, then read-only backing store.
- Guest writes to `/nix/store` do not go to host `/nix/store`; host impact is mainly extra store read activity.

**`--no-host-nix-store`** switches to a fully guest-managed store:
- Better isolation: host store paths are not mounted into the guest.
- Trade-offs: slower startup (cannot reuse host store paths), guest must fetch more paths itself, higher disk usage.

#### Secrets access

Anyone can run `run-hetzci-vm`, but secrets are only decrypted when the user owns the secret key of one of the age public keys declared in [`.sops.yaml`](../../.sops.yaml). Otherwise, the VM boots without secrets and [the user is notified](../../nix/apps.nix). To request access, generate an age key following [this documentation](https://github.com/tiiuae/ci-vm-example?tab=readme-ov-file#generating-and-adding-an-admin-sops-key) and send a PR adding your key to `.sops.yaml`.

#### Port forwarding

The VM automatically forwards:
- **SSH**: host port 2222 → guest port 22
- **Jenkins**: host port 8080 → guest port 80

```bash
# SSH into the VM
❯ ssh -p 2222 localhost
```

The Jenkins web interface is available at http://127.0.0.1:8080 while the VM is running.

To stop the VM, use `Ctrl-a` `x` or run `shutdown now` in the VM terminal.

### Deploy Changes to dev

**Important**: sync with the team before deploying to `dev` to avoid interfering with someone else's testing.

After testing locally in a VM, configure any environment-specific values in the
`dev` directory and [deploy](../../docs/deploy-rs.md):

```bash
❯ deploy -s .#hetzci-dev
```

This deploys to https://ci-dev.vedenemo.dev.

### Deploy Changes to prod

**Important**: only deploy `prod` from ghaf-infra main. Sync with the team beforehand to avoid interfering with ongoing production testing.

After testing locally in a VM and optionally in `dev`, deploy the reviewed
configuration from the main branch:

```bash
❯ deploy -s .#hetzci-prod
```

This deploys to https://ci-prod.vedenemo.dev.

### Verify Deployed Version

Check that the deployed git revision matches what you expect:

```bash
❯ ssh ci-dev.vedenemo.dev 'nixos-version --configuration-revision'
```

### Connect Test Agents

On non-VM environments, manually connect the test HW agents to the deployed Jenkins host. Find the relevant testagent IP address in [`hosts/machines.nix`](../machines.nix) and connect:

```bash
# Connect testagent-dev agents to the ci-dev Jenkins instance
❯ ssh 172.18.16.33 connect https://ci-dev.vedenemo.dev
```

## Release Environment Setup

The release environment is completely re-installed for each Ghaf release to support ephemeral release builds. See the [`install-release` task](../../docs/tasks.md#install-release) for automation details.

## Jenkins Pipeline Overview

All pipelines can be tested locally in the `vm` environment, but no testagents
can connect to localhost so HW tests will not run. The release environment uses
the `ghaf-release` Cachix cache; other environments with the Cachix integration
enabled use `ghaf-dev`.

#### ghaf-hw-test
Runs Ghaf hw-tests given a ghaf image and a testset. Can be triggered manually to run a hw-test ad-hoc.

#### ghaf-hw-test-manual
Pipeline to help Ghaf HW test development.

#### ghaf-main
Runs on push to Ghaf main. Triggered by a GitHub webhook sent to `prod` environment.

#### ghaf-manual
Allows manually triggering a set of Ghaf builds and optionally running a specified set of hw-tests against the builds.

#### ghaf-nightly
Triggers the main nightly builds and tests on schedule.

#### ghaf-nightly-perftest
Triggers performance tests nightly on schedule.

#### ghaf-nightly-poweroff
Powers off test devices nightly on schedule.

#### ghaf-pre-merge
Runs on all changes to Ghaf PRs authored by tiiuae organization members. Triggered by a GitHub webhook sent to `prod` environment.

#### ghaf-pre-merge-manual
Allows manually triggering a pre-merge check given a Ghaf PR number. Optionally writes the check status to GitHub PR.

#### ghaf-release-candidate
Manually triggered pipeline to build and test a ghaf release candidate.

#### ghaf-release-publish
Manually triggered pipeline to publish a ghaf release candidate. Includes stages such as pinning the release for OTA and archiving the release content to permanent storage.
