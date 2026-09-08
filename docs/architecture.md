<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture Overview

This document describes the high-level architecture of the
[Ghaf](https://github.com/tiiuae/ghaf) CI/CD infrastructure. For operational
procedures and per-component details, see the [cross-references](#cross-references)
at the end.

## Host Overview

The canonical host inventory lives in
[`hosts/machines.nix`](../hosts/machines.nix). It records host modules, target
systems, and machine metadata such as IPs, SSH keys, and Nebula addresses. The
sections below group hosts by role and describe how they relate to one another.

### Jenkins Controllers

Four Hetzner Jenkins controllers serve different stages of the development
lifecycle. Each runs behind an OAuth2 Proxy that authenticates users via
ghaf-auth and exposes a public web UI over Caddy with ACME TLS.

| Host | URL | Purpose |
|---|---|---|
| `hetzci-prod` | ci-prod.vedenemo.dev | Production CI: runs on every push and PR to Ghaf |
| `hetzci-dev` | ci-dev.vedenemo.dev | Development CI: for CI and hardware-test development |
| `hetzci-release` | ci-release.vedenemo.dev | Release CI: ephemeral, re-installed per release cycle |
| `hetzci-dbg` | ci-dbg.vedenemo.dev | Debug CI: isolated controller/builder environment for troubleshooting |

The `hetzci-vm` configuration runs locally (`localhost:8080`) via
`nix run .#run-hetzci-vm` as a QEMU VM for developing and testing CI changes
before deploying to a real environment. It is not a deploy target.

GitHub webhooks deliver push and PR events to `hetzci-prod`. The release
controller has no webhooks; its pipelines are triggered manually. Each
controller dispatches Nix builds to its configured remote builders and
connects to test agents over the Nebula overlay.

### Remote Builders

Builders are high-resource Hetzner machines that compile Nix derivations on
behalf of Jenkins controllers, GitHub Actions, and individual developers.
Prod and dev share builders; release and debug use separate builder sets.

| Host | Arch | Used by |
|---|---|---|
| `hetz86-1` | x86_64 | `hetzci-prod`, `hetzci-dev` |
| `hetz86-builder` | x86_64 | GitHub Actions, developer remote builds (builder.vedenemo.dev) |
| `hetzarm` | aarch64 | `hetzci-prod`, `hetzci-dev`, GitHub Actions, developer remote builds |
| `hetz86-rel-2` | x86_64 | `hetzci-release` |
| `hetzarm-rel-1` | aarch64 | `hetzci-release` |
| `hetz86-dbg-1` | x86_64 | `hetzci-dbg` |
| `hetzarm-dbg-1` | aarch64 | `hetzci-dbg` |

Build results are pushed to three Cachix binary caches:

- **[`ghaf-dev`](https://app.cachix.org/organization/tiiuae/cache/ghaf-dev)**:
  the main development cache. The `cachix-push` service on `hetz86-1` and
  `hetzarm` uploads new store paths, subject to the image and referrer filters
  in `hosts/builders/cachix-push.sh`. Since `hetzarm` also serves GitHub
  Actions and developer builds, the cache can contain their outputs too.
  The push service does not check PR authorship.
- **[`ghaf-dbg`](https://app.cachix.org/organization/tiiuae/cache/ghaf-dbg)**: populated by the debug controller/builders and consumed by those
  hosts, keeping dbg-published results isolated from the main development
  cache.
- **[`ghaf-release`](https://app.cachix.org/organization/tiiuae/cache/ghaf-release)**: populated exclusively by the release environment. The
  ephemeral release controller and builders pull earlier build results from this
  cache so that only changed derivations need to be rebuilt.

### Test Agents

Test agents are on-prem machines in the Tampere office with physical hardware
devices (Orin AGX/NX, Lenovo X1, etc.) attached. They connect to Jenkins
controllers over the Nebula overlay and run one Jenkins agent service per
device, effectively acting as a lock for each piece of hardware.

| Host | Variant | Hardware |
|---|---|---|
| `testagent-dbg` | dbg | Orin NX |
| `testagent-dev` | dev | Orin AGX, Orin NX, Orin AGX-64, Lenovo X1, Darter Pro |
| `testagent-prod` | prod | Lenovo X1, Darter Pro |
| `testagent2-prod` | prod | (secondary prod agent) |
| `testagent-release` | release | Orin AGX, Orin NX, Lenovo X1, Darter Pro |

Each agent also runs:

- [BrainStem](https://acroname.com/software/brainstem-development-kit): CLI
  tools and udev rules for controlling Acroname programmable USB hubs (used for
  power-cycling and USB switching of test devices)
- `policy-checker`: a Go wrapper around `verify-signature` that validates SLSA
  provenance and image signatures before flashing

Agents expose relay-board metrics (port 8000) and push logs to Loki via Alloy.
They are monitored by `ghaf-monitoring` through the Nebula overlay.

### Supporting Services

| Host | Service | Purpose |
|---|---|---|
| `ghaf-auth` | [Dex](https://dexidp.io/) OIDC provider | Central authentication backed by GitHub org membership |
| `ghaf-monitoring` | Prometheus, Grafana, Loki | **Infrastructure** metrics, dashboards, log aggregation, and alerting (monitoring.vedenemo.dev) |
| `ghaf-log` | Grafana + Loki | **Ghaf device** log analysis (ghaflogs.vedenemo.dev) |
| `ghaf-lighthouse` | Nebula lighthouse | Overlay network discovery and DNS for `sumu.vedenemo.dev` |
| `ghaf-registry` | [Zot](https://zotregistry.dev/) OCI registry | Container image registry (registry.vedenemo.dev), OIDC-authenticated via ghaf-auth |
| `ghaf-webserver` | Nginx | Static web content (vedenemo.dev) |
| `ghaf-fleetdm` | [Fleet](https://fleetdm.com/) (fleetdm.vedenemo.dev) | Device management server for Ghaf end-devices. Test agents carry enrollment credentials (via sops) so that Ghaf images flashed during CI testing can register with Fleet |

### NetHSM Gateways

CI builds use hardware security modules (HSMs) for two independent signing
purposes:

- **SLSA signing**: disk images and provenance files are signed for supply
  chain integrity. This uses `openssl` with ECDSA/EDDSA keys stored on the
  NetHSM.
- **UEFI Secure Boot signing**: EFI binaries and boot images are signed so
  they pass Secure Boot verification on target hardware. This uses
  `uefisign`/`systemd-sbsign` with RSA keys stored on the HSM.

Both operations go through the same PKCS#11 proxy infrastructure, but use
different keys and tools. See [NetHSM hardware signing](./nethsm.md) for key
names, signing commands, and UEFI key enrollment.

The signing keys are stored on dedicated
[NetHSM](https://www.nitrokey.com/products/nethsm) hardware, physically
isolated from the CI network. Gateway hosts bridge this gap: each sits on an
isolated ethernet segment with the NetHSM appliance and exposes a PKCS#11
interface over the Nebula overlay so that Jenkins controllers can request
signing operations without direct access to the HSM.

| Host | Location | NetHSM address |
|---|---|---|
| `nethsm-gateway` | Tampere office | 10.255.255.1 (isolated link per gateway) |
| `nethsm-gateway-dev` | Tampere office | 10.255.255.1 (isolated link per gateway) |
| `uae-nethsm-gateway` | UAE site | 192.168.70.20 (isolated ethernet) |

Each gateway runs a `pkcs11-proxy` daemon on a TLS port reachable from the
Nebula network. Requests are encrypted with a host-specific key from sops
secrets.

### UAE Site

A parallel set of infrastructure in the UAE mirrors parts of the Hetzner setup
and connects back via the Nebula overlay.

| Host | Purpose |
|---|---|
| `uae-azureci-prod` | Azure-hosted Jenkins controller (ci-prod.uaenorth.cloudapp.azure.com) |
| `uae-azureci-az86-1` | x86_64 builder in Azure for uae-azureci-prod |
| `uae-azureci-hetzarm-1` | ARM builder in Hetzner UAE for uae-azureci-prod |
| `uae-testagent-prod` | On-prem test agent with Intel hardware devices |
| `uae-testagent2-prod` | On-prem test agent with Orin hardware devices |
| `uae-lab-node1` | Lab node with Kubernetes tooling |
| `uae-nethsm-gateway` | NetHSM signing gateway (see above) |
| `uae-azureci-dev` | Azure-hosted Dev Jenkins controller (ci-dev.uaenorth.cloudapp.azure.com) |
| `uae-azureci-registry` | UAE [Zot](https://zotregistry.dev/) OCI registry in Azure (registry.uaenorth.cloudapp.azure.com), OIDC-authenticated via ghaf-auth |

## CI/CD Pipeline Flow

Changes to the Ghaf repository trigger two parallel build paths:

### Jenkins Pipeline

1. **Trigger**: a push or PR to the [Ghaf](https://github.com/tiiuae/ghaf)
   repo sends a GitHub webhook to the **prod** Jenkins controller.
2. **Build**: Jenkins dispatches Nix builds to the shared prod/dev builders
   (`hetz86-1`, `hetzarm`). [sbomnix](https://github.com/tiiuae/sbomnix)
   generates SBOMs and SLSA provenance on the controller, and build
   artifacts are signed via the [NetHSM](#nethsm-gateways).
3. **Test**: built images are deployed to on-prem test agents over the Nebula
   overlay. Each agent houses physical hardware devices and runs one Jenkins
   agent service per test device.
4. **Results**: test results flow back to Jenkins and build status is
   reported on the GitHub PR.

The **release** environment is ephemeral: it is fully re-provisioned with
`inv install-release` for each Ghaf release, giving it a clean state. It has
its own dedicated builders and test agents, and is the only environment
authorized to push to the `ghaf-release` binary cache. Because the cache
persists across re-installs, release builds can reuse earlier results and only
rebuild what has changed. The **dev** environment mirrors prod for CI and test
development. The **dbg** controller and its dedicated builders only trust
their own `ghaf-dbg` cache alongside `cache.nixos.org`, and only publish into
`ghaf-dbg`. The `testagent-dbg` host currently still inherits the default
`ghaf-dev` cache configuration.

Having a self-hosted CI solution alongside GitHub Actions ensures Ghaf
is not fully dependent on a third-party service for build and test
infrastructure.

### GitHub Actions

Pushes and PRs to Ghaf `main` also trigger a
[GitHub Actions workflow](https://github.com/tiiuae/ghaf/blob/main/.github/workflows/build.yml)
that compiles a matrix of build targets across x86_64 and aarch64. The workflow
uses `nix-fast-build --remote` over SSH to offload compilation to
`hetz86-builder` and `hetzarm`, the shared builders available for developer
remote builds. This workflow checks builds without running hardware tests.
Build status appears directly on PRs and commits in GitHub without requiring
access to Jenkins.

### Release artifact storage

During builds, Jenkins stores artifacts (disk images, SLSA provenance,
signatures, test results) locally under `/var/lib/jenkins/artifacts/` on the
controller. For releases, the `ghaf-release-publish` pipeline verifies all
signatures, packages the artifacts into tarballs, and uploads them to Hetzner
Object Storage (an S3-compatible service, bucket `ghaf-artifacts`) using
minio-client. The [ghaf-archive](https://github.com/tiiuae/ghaf-archive) web
application provides a browsable frontend to the archived releases.

Release image artifacts also get a signed release-policy attestation after
their configured hardware tests have completed. The policy is configured in
`slsa/release-policy.yaml`; each criterion runs, and the `required` flag
determines whether a failed criterion fails the release step. The attestation
records the per-criterion result for image signature verification, SLSA
provenance verification, the pre-test provenance trust policy verdict saved in
`test-results.json`, SBOM presence, and hardware test status. Jenkins signs the
attestation with the SLSA provenance signing key and publishes it as an OCI
referrer without changing the already-published target manifest. Release
archival requires a passing signed release-policy attestation by default and can
be bypassed only by setting
`REQUIRE_RELEASE_ATTESTATION=false` for transitional use.

### Repository CI (ghaf-infra)

The ghaf-infra repository has its own GitHub Actions workflows
(`.github/workflows/`) for quality gates and security scanning.

**PR and push checks:**

- `check.yml`: runs `nix flake check` on PRs and pushes to main
  with `--option allow-import-from-derivation false --no-build` (evaluation only).
- `test-ghaf-infra.yml`: builds all NixOS configurations for x86_64 and
  aarch64 using remote builders, and runs the pre-commit checks on x86_64.
- `authorize.yml`: reusable authorization workflow. PRs from `tiiuae` org
  members are auto-approved; external PRs require manual approval before
  CI runs.
- `warn-on-workflow-changes.yml`: intentionally fails if `authorize.yml`
  or `test-ghaf-infra.yml` are modified in a PR, since those changes only
  take effect after merge.

**Security scanning and attestations:**

- `source-vsa.yml`: issues Source Verification Summary Attestations (VSAs)
  on pushes to main using `slsa/source-vsa-policy.yaml`. It uses GitHub OIDC
  (`id-token: write`) for signing and publishes the attestations to GHCR.
- `actions-security-analysis.yml`: runs [zizmor](https://woodruffw.github.io/zizmor/)
  to audit workflow files for security issues.
- `dependency-review.yml`: blocks PRs that introduce known-vulnerable
  dependencies.
- `flakevuln.yml`: scheduled and manual vulnerability scanning for the
  ci-prod environment: the `hetzci-prod` controller, its `hetz86-1` (x86) and
  `hetzarm` (aarch64) remote builders, and `ghaf-auth`.
- `scorecards.yml`: [OSSF Scorecard](https://securityscorecards.dev/)
  supply chain security analysis.

**Automation:**

- `update-robot-framework.yml`: daily automated PR to bump the
  robot-framework flake input.
- `update-flake-inputs.yml`: weekly automated PR to update all flake inputs
  and Jenkins plugin manifests.
- Dependabot (`.github/dependabot.yml`) keeps GitHub Actions and Go module
  dependencies up to date.

## Network Architecture

The infrastructure spans three network tiers:

| Tier | Subnet | Purpose |
|---|---|---|
| Public internet | Public IPs | Jenkins UIs, Grafana, web services (ACME TLS via Caddy) |
| Hetzner internal | `10.0.0.0/24` | Cloud-to-cloud communication between Hetzner hosts |
| Nebula overlay | `10.42.42.0/24` | Encrypted tunnel connecting Hetzner, Tampere office, and UAE site |

**Nebula** traffic flows directly between hosts, not through the lighthouse.
The lighthouse (`ghaf-lighthouse`) is only a discovery node. It also serves
as a DNS server for the `sumu.vedenemo.dev` subdomain, resolving Nebula
addresses within the overlay.

Hosts with Nebula addresses are listed under `nebula_ip` in
`hosts/machines.nix`: the Hetzner Jenkins controllers (`hetzci-prod`,
`hetzci-dev`, `hetzci-dbg`, `hetzci-release`), the UAE Azure controllers
(`uae-azureci-prod`, `uae-azureci-dev`), the test agents (`testagent-dbg`,
`testagent-dev`, `testagent-prod`, `testagent2-prod`, `testagent-release`),
all three NetHSM gateways, `ghaf-monitoring`, and `ghaf-lighthouse`. The UAE
test agents are not enrolled in Nebula.

Remote builders (`hetz86-1`, `hetz86-builder`, `hetzarm`, etc.) rely on public
IPs or the Hetzner internal network and have no Nebula connectivity. They
cannot reach on-prem hardware through the overlay; Jenkins controllers
provide that connection.

See [Nebula overlay network](./nebula.md) for certificate management and
configuration details.

## Authentication

Jenkins and the OCI registries use a central OIDC provider; Grafana uses
GitHub OAuth directly:

- **ghaf-auth** runs [Dex](https://dexidp.io/) with a GitHub connector backed
  by the `devenv-fi`, `phone`, and `ci-dev-admins` teams in `tiiuae`.
- Jenkins controllers sit behind [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/),
  which validates tokens with ghaf-auth before forwarding requests to Jenkins.
- The OCI registries authenticate through ghaf-auth. Grafana connects to
  GitHub directly, with its own organization and team restrictions.

See [Jenkins authentication](./jenkins-authentication.md) for the full
auth flow and secret generation.

## Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
encrypted with [age](https://age-encryption.org/) keys:

- Each host has a `secrets.yaml` containing its encrypted secrets.
- `.sops.yaml` at the repo root maps secrets to the age keys (admin users +
  host keys) that can decrypt them.
- On boot (or `nixos-rebuild switch`), sops-nix automatically decrypts secrets
  and places them at configured file paths.
- Each host's private SSH key is stored as a sops secret and automatically
  deployed on [host installation](./tasks.md#install). The age key used for
  decryption is derived from this SSH host key.
- `secrets.yaml` files are created and edited with the `sops` CLI tool.
- Admin key changes require running `inv update-sops-files` to re-encrypt all
  secrets with the updated key set.

Plaintext secrets are **never** committed to the repository. The secrets
configuration was originally adopted from the
[nix-community infra](https://github.com/nix-community/infra) project.

## Monitoring and Logging

`ghaf-monitoring` runs Prometheus, Grafana, and Loki on a dedicated Hetzner
volume.

**Metrics collection** (Prometheus scrape jobs):

The target lists are defined in
[`hosts/ghaf-monitoring/configuration.nix`](../hosts/ghaf-monitoring/configuration.nix).

| Job | Transport | Hosts |
|---|---|---|
| `hetzner-cloud` | Hetzner internal network (direct) | Configured Hetzner Cloud VMs, node-exporter on port 9100 |
| `hetzner-robot` | SSH proxy (`sshified`) | Configured dedicated servers, node-exporter on port 9100 |
| `office` | Nebula overlay | Tampere test agents and `nethsm-gateway`, node-exporter on port 9100 |
| `relay-board` | Nebula overlay | `testagent-dev`, `testagent2-prod`, `testagent-release`, port 8000 |
| `nethsm` | Nebula overlay | `nethsm-gateway`, `uae-nethsm-gateway`, port 8000 |
| `zot` | HTTPS with basic auth over the Hetzner internal network | `ghaf-registry`, port 443 |
| `nebula` | Hetzner internal network or Nebula overlay | All hosts with `nebula_ip`, Nebula metrics on port 9101 |
| `uae` | Nebula overlay | `uae-azureci-prod`, `uae-nethsm-gateway`, node-exporter on port 9100 |

**Logging**: hosts with `services.monitoring.logs.enable` run Grafana Alloy
agents that push systemd journal logs to Loki on `ghaf-monitoring`. Alerting
is configured to notify a Slack channel.

**`ghaf-log`** (ghaflogs.vedenemo.dev) is a separate Grafana + Loki instance
for Ghaf device logs, independent from the infrastructure monitoring on
`ghaf-monitoring`. It exposes a basic-auth Loki API at
`loki.ghaflogs.vedenemo.dev` for external log producers.

All Grafana dashboards and alerts are provisioned declaratively through Nix;
manual edits in the Grafana UI are not persisted.

See [Monitoring](./monitoring.md) for development and debugging details.

## Deployment

| Method | Use case |
|---|---|
| [`deploy-rs`](./deploy-rs.md) | Push configuration changes to running hosts (with automatic rollback) |
| [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere) + [`disko`](https://github.com/nix-community/disko) | Initial provisioning: partitions disks and installs NixOS |
| [`invoke` tasks](./tasks.md) | Operational workflows (`inv install`, `inv reboot`, `inv update-sops-files`, `inv install-release`, etc.) |

## Cross-References

- [Deployment tasks](./tasks.md): install, reboot, and other invoke tasks
- [Deploying with deploy-rs](./deploy-rs.md): deploying configuration changes
- [Monitoring](./monitoring.md): Grafana, Prometheus, and Loki setup
- [Nebula overlay network](./nebula.md): overlay network and certificate management
- [NetHSM hardware signing](./nethsm.md): PKCS#11 proxy and signing operations
- [Jenkins authentication](./jenkins-authentication.md): OIDC auth flow
- [Jenkins test agents](./jenkins-testagents.md): on-prem test agent setup
- [Jenkins CI development](../hosts/hetzci/README.md): CI environments and pipeline overview
- [`hosts/machines.nix`](../hosts/machines.nix): canonical host inventory (modules, systems, deploy metadata, IPs, keys, Nebula addresses)
