<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf Jenkins CI in Hetzner

This directory contains the configuration for Ghaf Jenkins CI in Hetzner.

## Getting Started

This document assumes you have [`nix`](https://nixos.org/download.html) with flakes support.

Clone this repository:
```bash
❯ git clone https://github.com/tiiuae/ghaf-infra.git
❯ cd ghaf-infra
```

Bootstrap nix shell with the required dependencies:
```bash
❯ nix develop
```

All example commands in this document are executed from this nix shell.

## Directory Structure
```
hosts/hetzci/
├── dev
|   └── ...
├── prod
|   └── ...
├── release
|   └── ...
└── vm
    ├── casc
    │   ├── jenkins-casc.yaml
    │   └── pipelines
    │       ├── ghaf-manual.groovy
            ...
    │       └── modules
    │           └── utils.groovy
    ├── configuration.nix
    └── secrets.yaml

```
Each subdirectory under [`hosts/hetzci`](https://github.com/tiiuae/ghaf-infra/tree/main/hosts/hetzci) contains the configuration for the given hetzci environment. Configuration for each environment follows the same structure:
- `casc` directory contains the jenkins configuration-as-code config, with the main configuration at `casc/jenkins-casc.yaml`
- `casc/pipelines` contains the jenkins pipelines and pipeline modules for the specific environment
- `configuration.nix` is the nixosConfiguration for the jenkins host
- `secrets.yaml` encrypted sops secrets specific to given environment

There are four independent hetzci environments: `dev`, `prod`, `release`, and `vm` each in its own subdirectory:
- `release`: release jenkins CI to support ghaf release builds. The `release` jenkins web interface is available at: https://ci-release.vedenemo.dev/.
- `prod`: production jenkins CI to support ghaf development activities. The `prod` jenkins web interface is available at: https://ci-prod.vedenemo.dev/
- `dev`: development jenkins CI to support ghaf-infra and ghaf hw-test development activities. The `dev` jenkins web interface is available at: https://ci-dev.vedenemo.dev/
- `vm`: configuration which can be run in Qemu VM locally to support testing hetzci changes in a local VM before deploying to `dev` or `prod`. The configuration is modified to allow local testing, as an example: `caddy` service configuration is simplified, `jenkins` configuration is modified to not require authentication, and `getty` automatically logs in as root.

We want to keep the configurations fully independent in each environment to be able to test changes in non-prod environment(s) before promoting the change to `prod` or `release`. For this reason, many parts of the hetzci configuration need to be duplicated between the different configuration subdirectories. On developing a configuration change, we anticipate the change is first introduced in `vm` subdirectory, then moves forward to `dev`, and finally copied over to `prod` and `release` as explained below. Both the `prod` and `release` should only be deployed from the ghaf-infra main branch, thus never running configurations that would not have gone through the review process and preferrably some testing in `dev` first.

## Usage

Following sections describe the intended workflow for hetzci development.

### Develop and Test Changes Locally in a VM

```bash
❯ nix flake show
...
├───apps
│   └───x86_64-linux
│       └───run-hetzci-vm: app
...
```
Flake apps target [`run-hetzci-vm`](https://github.com/tiiuae/ghaf-infra/blob/79ea3c3e8b7426a71c39bab64ffcfb99c259a143/nix/apps.nix#L64-L69) allows running [`hosts/hetzci/vm`](https://github.com/tiiuae/ghaf-infra/tree/main/hosts/hetzci/vm) configuration locally in a Qemu VM decrypting the host sops secrets following the rules set in [`.sops.yaml`](https://github.com/tiiuae/ghaf-infra/blob/main/.sops.yaml). The general idea is explained in [tiiuae/ci-vm-example](https://github.com/tiiuae/ci-vm-example?tab=readme-ov-file#secrets).

On running the VM target, a disk file (.qcow2) will be created on the current working directory. Any state data accumulated on the VM will persist as long as the associated disk file is not removed. For instance, changes to virtual machine's `/nix/store` will persist reboots as long as the disk file is not removed between the VM boot cycles. Similarly, the VM state can be cleared by removing the VM .qcow2 disk file on the host.

To run the `hosts/hetzci/vm` config in a local Qemu VM, execute the `run-hetzci-vm` target:

```bash
❯ nix run .#run-hetzci-vm

# Or, to start the VM with clean state:
❯ rm -f hetzci-vm.qcow2; nix run .#run-hetzci-vm
```
Which starts a headless VM with a console in the current terminal.

Note: the `run-hetzci-vm` app target in this flake can be run by anyone, but only when run by a user that owns the secret key of one of the age public keys declared in the relevant section of [`.sops.yaml`](https://github.com/tiiuae/ghaf-infra/blob/f440c7fed409cd0ed73b4389e21751a92647d2e3/.sops.yaml#L166-L175) do the secrets get decrypted. In all other cases, the [user is notified](https://github.com/tiiuae/ghaf-infra/blob/f440c7fed409cd0ed73b4389e21751a92647d2e3/nix/apps.nix#L13-L20) and the VM will boot-up without secrets. To request access to relevant sops secrets, generate an age key following instructions from [this documentation](https://github.com/tiiuae/ci-vm-example?tab=readme-ov-file#generating-and-adding-an-admin-sops-key) and send a PR adding your key to [`.sops.yaml`](https://github.com/tiiuae/ghaf-infra/blob/f440c7fed409cd0ed73b4389e21751a92647d2e3/.sops.yaml#L166-L175).

`hetzci-vm` configuration automatically sets port forwarding to allow accessing `ssh` over [host port 2222](https://github.com/tiiuae/ghaf-infra/blob/79ea3c3e8b7426a71c39bab64ffcfb99c259a143/hosts/default.nix#L133) and `jenkins` web interface over [host port 8080](https://github.com/tiiuae/ghaf-infra/blob/79ea3c3e8b7426a71c39bab64ffcfb99c259a143/hosts/default.nix#L128).
As an example, to ssh from host to guest, you would run:
```bash
# To access the guest ssh from your localhost
❯ ssh -p 2222 localhost
```
Similarly, while the VM is running, you can access the VM jenkins interface locally over URL http://127.0.0.1:8080.

To stop the VM, use `Ctrl-a` `x` or command `shutdown now` in the VM terminal.

### Deploy Changes to dev

After testing changes locally in a VM as explained above, copy the same changes to the `dev` directory and deploy following the documentation in [deploy-rs.md](https://github.com/tiiuae/ghaf-infra/blob/main/docs/deploy-rs.md):

```bash
❯ deploy -s .#hetzci-dev
```

Which would deploy the changes to https://ci-dev.vedenemo.dev

### Deploy Changes to prod

After testing changes locally in a VM and optionally in a `dev` environment as explained above, copy the same changes to `prod` directory and deploy:
```bash
❯ deploy -s .#hetzci-prod
```

Which would deploy the changes to https://ci-prod.vedenemo.dev

### Verify Deployed Version

Ensure the git revision deployed on the target host matches the git revision you expect:
```bash
# Run the 'nixos-version --configuration-revision' on the deployed remote
# host to show the deployed git revision on remote. Below, we use
# ci-dev.vedenemo.dev as an example:
❯ ssh ci-dev.vedenemo.dev  'nixos-version --configuration-revision'
f440c7fed409cd0ed73b4389e21751a92647d2e3
```

### Connect Test Agents

On non-VM environments, you need to manually connect the test HW agents to the deployed Jenkins host.
Find the relevant testagent IP address at [`hosts/machines.nix`](https://github.com/tiiuae/ghaf-infra/blob/f440c7fed409cd0ed73b4389e21751a92647d2e3/hosts/machines.nix#L76-L94) and connect the test HW to the deployed environment:

```bash
# Run the connect script on remote testagent to connect the test devices.
# Below example connects the testagent-dev agents to ci-dev Jenkins instance:
❯ ssh 172.18.16.33 connect https://ci-dev.vedenemo.dev
...
CONTROLLER=https://ci-dev.vedenemo.dev
Connected agents to the controller
```

## Release Environment Setup

The release environment is completely re-installed for each Ghaf release to support ephemeral release builds.
See the [`install-release` task](https://github.com/tiiuae/ghaf-infra/blob/main/docs/tasks.md#install-release) that helps automate the release environment setup.

## Jenkins Pipeline Overview

All pipelines can be tested locally in the `vm` environment, but obviously no testagents can connect to your localhost, so HW tests would not run for pipelines triggered in a VM. Also, only the ci-release environment is authorized to push to the [release cache](https://app.cachix.org/organization/tiiuae/cache/ghaf-release), so cachix push is expected to fail on running the `ghaf-release` pipeline in the VM environment.

#### ghaf-hw-test
Runs Ghaf hw-tests given a ghaf image and a testset. Can be triggered manually to run a hw-test ad-hoc.

#### ghaf-hw-test-manual
Pipeline to help Ghaf HW test development.

#### ghaf-main
Runs on push to Ghaf main. Triggered by a GitHub webhook sent to `prod` environment.

#### ghaf-manual
Allows manually triggering a set of Ghaf builds and optionally run a specified set of hw-tests against the builds.

#### ghaf-nightly
Triggers the main nightly builds and tests on schedule.

#### ghaf-nightly-perftest
Triggers performance tests nightly on schedule.

#### ghaf-pre-merge
Runs on all changes to Ghaf PRs authored by tiiuae organization members. Triggered by a GitHub webhook sent to `prod` environment.

#### ghaf-pre-merge-manual
Allows manually triggering a pre-merge check given a Ghaf PR number. Optionally writes the check status to GitHub PR.

#### ghaf-release
Manually triggered pipeline to build and test ghaf releases.
