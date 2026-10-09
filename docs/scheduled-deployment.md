<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scheduled deployment automation (draft plan)

Status: draft for discussion. Nothing described here is implemented.

This plan proposes how ghaf-infra hosts deploy their own configuration on a
regular schedule, for example weekly, and only when the host is idle or
otherwise safe to update. Hosts are enrolled one at a time, and each enrolled
host has its own schedule. The plan covers the runner model and credentials,
which hosts to enroll, schedules, per-host safe-to-deploy conditions,
post-deploy checks, rollback, and reporting. Destructive flows such as
`inv install` and `inv install-release --reinstall` stay out of unattended
automation.

## Current state

- Deployments are pushed manually with [deploy-rs](./deploy-rs.md) from an
  administrator's machine. deploy-rs logs in as the administrator's own user
  and activates through passwordless `sudo`; root SSH login is disabled.
- ghaf-infra and all of its flake inputs are public GitHub repositories. Each
  host already decrypts its sops secrets with its own host key.
- `inv print-revision` and `inv reboot --needs-reboot` treat a host as needing
  a reboot when the booted kernel, initrd or kernel modules differ from the
  next-boot system profile.
- `system.switch.inhibitors.nixos-release` refuses a live switch across NixOS
  releases; such upgrades need a boot deployment and a reboot.
- The ci-dbg and ci-release hosts use [baseline reset](./baseline-reset.md): a
  deployment fully takes effect only after a reboot, `/var/lib` is reset on
  every boot, and deploy-rs rollback is not supported.
- The ci-release hosts are deployed only through `inv install-release`, which
  also starts a fresh builder credential epoch.
- Hosts use UTC. Prod Jenkins runs `ghaf-nightly` at 20:00 and
  `ghaf-nightly-perftest` at 00:00, and polls for pre-merge builds every 15
  minutes, so nights are not automatically quiet.
- Most hosts ship their journal to Loki, and Grafana alerts go to Slack (see
  [monitoring](./monitoring.md)). node-exporter runs with the `systemd`
  collector. Some hosts are not scraped by Prometheus at all (see
  [enrollment](#enrollment)).
- `trim-profiles` keeps the three newest system generations.
- Configurations from unmerged branches are sometimes deployed manually, for
  example to test on ci-dbg. Automation must not silently overwrite them.

## What the automation is for

Authors keep deploying their own changes manually after merging, as today.
The automation mostly catches hosts up: weekly flake input and security updates,
and shared-module changes on hosts nobody touched. Hosts deploy independently,
so different hosts can run different `main` commits, at most about a week
apart. deploy-rs remains the tool for urgent deployments, for changes that span
hosts, and for hosts that are not enrolled.

## Runner model

| Model | Credentials | Assessment |
|---|---|---|
| GitHub-hosted Actions running deploy-rs | A key with root access to every host, stored in GitHub | Rejected: puts fleet-wide root in a third-party service, and cannot reach the office test agents or the NetHSM gateways |
| Jenkins controller running deploy-rs | The same key on a controller | Rejected: controllers run CI jobs for Ghaf changes, including pre-merge builds |
| Dedicated runner host running deploy-rs | The same key on one hardened host | Possible, but compromising that host gives root on the whole fleet, and it needs network access to the office and the Nebula overlay |
| Pull: each host deploys itself on a timer | No new credentials | Proposed |

### Proposal: pull

Each enrolled host runs a systemd timer that selects a target commit, checks
that it is safe to deploy, builds its own configuration from that commit and
activates it. Because the repository and its inputs are public, no fetch
credential, deploy user, SSH key or sudo rule is added, and a compromised host
gains no access to other hosts.

Any deployment automation is root-equivalent on the hosts it updates: whoever
controls the commit the hosts pull controls the hosts. Today an administrator
sees what they deploy; unattended deployment removes that step, so
[which commit is deployed](#which-commit-is-deployed) is the central security
decision.

### Tooling

[comin](https://github.com/nlewo/comin) is a pull-based GitOps agent for
NixOS. The table compares it with a small ghaf-infra module built from a
systemd timer and `nixos-rebuild`, the same building blocks as NixOS
`system.autoUpgrade`:

| Requirement | comin | Own module |
|---|---|---|
| Per-host schedule | No: polls continuously (every 60 s by default) and deploys new commits | systemd timer (`OnCalendar`, `RandomizedDelaySec`) |
| Skip when busy | Not built in; deployments can require manual or timed confirmation | `ExecCondition=`: an exit code from 1 to 254 skips the run without failing the unit |
| Reboot when needed | Not handled; the `boot` operation only stages the system | Same rule as `inv reboot --needs-reboot`; `system.autoUpgrade` implements it with `allowReboot` |
| Commit signature verification | Yes, GPG or SSH allowed signers; only the tip commit must be signed | Would need to be added |
| Metrics | Prometheus exporter | Unit state through the node-exporter `systemd` collector; other values through the textfile collector |
| Downgrade protection | State in `/var/lib/comin`, reset on baseline-reset hosts unless persisted | Ancestry checks, see below |
| Footprint | An additional root daemon, pre-1.0 at the time of writing | Built-in NixOS components |

Proposal: start with the own module. Revisit comin if the team moves to
deploy-on-merge or adopts signed commits. Signature verification is comin's
main advantage, but it helps only if commits on the deployed branch are signed,
which is not the case today.

Other tools considered: [Colmena](https://github.com/zhaofengli/colmena) and
[Clan](https://docs.clan.lol/) deploy from a CLI over SSH, so they share the
credential problem of a central runner.
[NixFleet](https://discourse.nixos.org/t/nixfleet-declarative-nixos-fleet-management-with-signed-gitops/77195)
and [nits](https://github.com/numtide/nits) are young or experimental.

## Which commit is deployed

| Option | Description | Trade-off |
|---|---|---|
| A. `main` | Deploy the head of `main` | Simplest. A change merged just before the window is deployed without anyone watching |
| B. Promotion branch | A scheduled workflow moves a `deploy` branch to the newest `main` commit that passed `test-ghaf-infra.yml` and has been on `main` for at least N hours | Adds a soak period, one auditable pointer and a freeze switch (pause the workflow). Needs a token that can push the branch |
| C. Signed commits or tags | Hosts deploy only commits signed by allowed keys | Strongest. Everyone who merges must sign; the allowed signers could be derived from `users/teams/devenv.nix` |

Decision: option A, at least initially. The target is the head of `main` when
the run starts; there is no minimum time on `main`.
Option B or C can be added later without changing the host-side checks below.

Within a run, the host pins the selected commit
(`git+https://github.com/tiiuae/ghaf-infra?rev=<sha>`) so that the checks and
the build use the same tree, and deploys only if:

- the target commit is reachable from `main`;
- the running `configurationRevision` is clean and is an ancestor of the
  target. This prevents downgrades, and a host running a manually deployed
  branch or dirty tree skips the deployment and reports itself as held;
- the system profile selected for the next boot has either the running
  revision or the target revision. Anything else, such as a manual
  `deploy --boot` from a branch or a deliberately staged older generation,
  holds the host. Compare revisions rather than store paths, because deploy-rs
  points the profile at a wrapper around the system;
- the target has not been rejected on this host (see
  [activation and rollback](#activation-and-rollback)).

## Enrollment

Hosts opt in individually in their own configuration. A host is enrolled only
when:

- Prometheus scrapes its node-exporter, so failed or skipped deployments can
  alert; it should also ship its journal to Loki;
- it can reach GitHub and the binary caches;
- its host-specific post-deploy checks are defined;
- the console path for recovery is known.

Not scraped by Prometheus today: `ghaf-webserver`, `ghaf-fleetdm`,
`nethsm-gateway-dev`, `hetzci-dbg`, `hetz86-dbg-1` and `hetzarm-dbg-1`.
`hetzci-dbg` also has log shipping disabled.

Proposed enrollment order. Hosts are enrolled one at a time, also within a
row, and the next host only after the earlier ones have deployed cleanly for a
few windows.

| Order | Hosts | Reason |
|---|---|---|
| 1 | `ghaf-log` | Monitored, ships logs, low impact, recoverable through the Hetzner console |
| 2 | `testagent-dbg` | First test agent: Jenkins drain and an office-hours reboot |
| 3 | `hetz86-dbg-1`, `hetzarm-dbg-1`, `hetzci-dbg` | Baseline-reset path, and a mirror of prod CI. Needs monitoring first |
| 4 | `ghaf-webserver`, `ghaf-fleetdm`, `nethsm-gateway-dev` | Low impact. Need monitoring first |
| 5 | `hetzci-dev`, `testagent-dev` | Dev CI |
| 6 | `ghaf-registry` | Prod pipelines publish to it |
| 7 | `hetz86-builder`, `hetzarm`, `hetz86-1`, `testagent-prod`, `testagent2-prod`, `hetzci-prod` | Production CI; the shared builders also serve GitHub Actions and developer builds |
| 8 | `nethsm-gateway`, `uae-nethsm-gateway`, `ghaf-auth`, `ghaf-lighthouse`, `ghaf-monitoring` | Signing, authentication for all services, Nebula discovery and DNS, and the alerting path. Jenkins falls back between the NetHSM gateways, so give them windows on different days. A failure on `ghaf-monitoring` can silence alerts, so its window stays in office hours. `uae-nethsm-gateway` also depends on the UAE [action point](#action-points) |

Not enrolled:

| Group | Hosts | Reason |
|---|---|---|
| Never automated | `hetzci-release`, `hetz86-rel-2`, `hetzarm-rel-1`, `testagent-release` | Deployed and reset only through `inv install-release`; a controller reboot loses its builder credentials |
| To be decided | Other `uae-*` hosts | Operated by another team; see [action points](#action-points) |

Hosts that are not enrolled still get the drift reporting described below.

## Schedules

Each enrolled host has a weekly deploy window, with a default per role that a
host can override in its configuration. The timer fires every 30 minutes inside
the window until the host has deployed or the window ends, so a host deploys
at most once per window. Each run selects the current head of `main`, so a fix
or revert merged during the window reaches the hosts that have not deployed
yet. A deployment that needs a reboot also reboots in the window.

Initially all windows are Tuesday 05:00 to 09:00 UTC, which is within office
hours in Tampere, so that problems are seen while people are around. Once a
host has deployed reliably, its window can move to the host's quiet time, for
example nights, after that time has been measured from the host's build or
usage history. Moving a window out of office hours accepts that a failed
reboot waits until morning, because alerts are handled by whoever reacts
first. Test agents, which may need physical access, and `ghaf-monitoring` stay
in office hours.

## Changes that span hosts

Some changes must reach several hosts together, for example a Dex client secret
on `ghaf-auth` and the matching oauth2-proxy configuration on the controllers,
builder SSH keys on a controller and its builders, Nebula certificates, or
Prometheus scrape targets. The pull request author is responsible for deploying
such a change manually to all affected hosts right after merging; the
automation then finds those hosts up to date.

To pause automation on a host, stop its timer for the current boot, or disable
automation in the host's configuration; that takes effect once the
configuration is deployed. Deploying or staging a branch manually also holds
the host, as described above. To stop a bad commit from reaching more hosts,
fix or revert it on `main`; hosts that already deployed it get the fix in their
next window, or sooner with a manual deployment. A run that is already building
or draining keeps its target, so also stop the deployment service on hosts
where a run is in progress; stopping it before activation ends the drain.

## Safe-to-deploy conditions

A deployment run has these steps:

1. Check the commit conditions above and the host conditions below as the
   service's `ExecCondition=`. Each skip is logged and exported with its
   reason.
2. Build the target. This does not affect running services.
3. Drain the host for its role, then confirm that it is idle.
4. Activate, run the post-deploy checks, and end the drain only after they
   pass.

Draining after the build keeps the drain short, and it stops new work from
starting between the idle check and activation.

On all enrolled hosts:

- the commit checks above pass;
- no systemd unit has already failed, so post-deploy checks start from a clean
  state;
- there is enough free space for the build.

Per role:

| Role | Condition |
|---|---|
| Jenkins controllers | Put Jenkins into quiet-down mode so that no new builds start, and wait until running builds finish. If they do not finish within a timeout, cancel quiet-down and retry later in the window. Cancel quiet-down after the post-deploy checks. The controller can query Jenkins locally on `127.0.0.1:8081` with the forwarded-header authentication the test agents already use; the group for these calls is to be decided |
| Builders | A switch does not interrupt running builds: NixOS restarts `nix-daemon` without stopping the processes that serve existing connections. A reboot requires the builder to be idle: no Nix builds and no remote build sessions for N minutes. Nothing stops a new remote build from arriving between that check and the reboot; such a build is interrupted, which is accepted because builds can be retried |
| Test agents | Mark the agent's device nodes temporarily offline on the controller so that they accept no new jobs, and wait until running jobs finish. The nodes stay offline through activation, reboot and post-deploy checks, and remain offline if the deployment fails. This needs a narrowly scoped permission on the controller, to be decided |
| Service hosts | Windows and post-deploy checks only |

Jenkins keeps quiet-down only in memory. If activation restarts Jenkins or
reboots the controller, queued builds could start before the post-deploy checks
pass, and a rollback would then interrupt them. The drain must therefore
survive the restart. For example, a marker file makes a Jenkins startup script
restore quiet-down, and the marker is removed only after the checks pass, so
Jenkins stays quiet if the deployment fails. On `hetzci-dbg` the marker must be
kept through `persistentFiles`. It is still to be verified that such a script
runs before the queue starts builds.

## Activation and rollback

- If the kernel, initrd or kernel modules differ from the booted system, or on
  baseline-reset hosts, where every deployment needs a reboot: make the target
  the boot default and reboot while the host is still drained.
- Otherwise switch to the target. If the release inhibitor refuses the switch,
  make the target the boot default and reboot instead.
- Post-deploy checks run after the switch and again after the reboot:
  - generic: no new failed units, the running `configurationRevision` equals
    the target, SSH is reachable, and Nebula is up where configured;
  - host-specific, declared with the host configuration, for example: the
    public Jenkins URL redirects to OAuth, the controller reports its builders
    as trusted, `ghaf-registry` answers on `/v2/`, Dex serves its discovery
    document, and builders answer `nix store ping`.
- Rollback after a switch: if the checks fail, the host switches back to the
  previous generation, does not reboot, and raises an alert. This replaces
  deploy-rs magic rollback, which needs an active deployer.
- Rollback after a reboot: a host that boots but fails its checks raises an
  alert, and an administrator decides whether to boot the previous generation.
  Baseline-reset hosts follow the [baseline reset](./baseline-reset.md)
  recovery guidance. A host that does not come back needs console access (the
  Hetzner console, or someone in the office for test agents). This is the main
  risk of unattended reboots, and the reason windows start in office hours;
  whether systemd-boot automatic boot assessment can reduce it on these hosts
  is still to be checked.
- A target that fails its post-deploy checks is recorded as rejected on the
  host, so later runs do not deploy it again. A different target gets a new
  attempt, and an administrator can clear the record to retry. On
  baseline-reset hosts, the record must be kept across reboots through
  `persistentFiles`.

## Reporting

- Deployment logs reach Loki on hosts with log shipping.
- Metrics per host: time of the last attempt and the last success, last result
  (deployed, skipped with reason, held, or failed), target, running and
  next-boot revision, any rejected target, and whether a reboot is pending.
- A Grafana dashboard shows every run. Alerts go to the existing Slack contact
  point only for states that need action: a failed deployment or rejected
  target, a host held or skipped for two windows in a row, and later a host
  more than N weeks behind `main`. Alerts keep firing until the cause is cleared, because no one is
  named as owner: whoever reacts first handles them.
- The metrics are useful before any host is enrolled: they show fleet drift,
  including on hosts that are never automated, without running
  `inv print-revision` from a workstation.

## Phases

1. Add drift metrics to all hosts (read-only), and add monitoring to the hosts
   that lack it.
2. Implement the module with a NixOS VM test that uses a local Git remote:
   deploy, skip when busy, hold when a branch is running or staged for the
   next boot, pick up a revert merged during the window, reboot when the kernel
   changes, revert on a failed check without redeploying the rejected target,
   and keep a controller drained across a Jenkins restart or reboot.
3. Enroll `ghaf-log`, run it for a few windows, and confirm that evaluation
   and build fit on the host.
4. Enroll the remaining hosts one at a time in the order above, move deploy
   windows to quiet hours where measured, and document operation in `docs/`.

## Decisions

1. Hosts deploy the head of `main` (option A), at least initially, with no
   minimum time on `main`.
2. Each host builds its own configuration, provided every enrolled host can.
   At the time of writing, evaluating a host configuration peaks at about
   0.7 GB of memory for service hosts and 1 GB for a Jenkins controller or test
   agent, and takes under 10 seconds once inputs are fetched. A dry run against
   an empty store shows that only small generated files (units, `/etc` files,
   scripts) are built locally; packages are fetched from `ghaf-dev` and
   `cache.nixos.org`. Hosts that do not use `ghaf-dev`, such as the ci-dbg
   controller, may have to build custom packages themselves.
3. Hosts are enrolled one at a time, each with its own weekly window, in which
   it also reboots when needed. The first windows are Tuesday 05:00 to 09:00
   UTC. A window can later move to quiet hours; test agents and
   `ghaf-monitoring` stay in office hours.
4. Alerts go to the existing Slack contact point with no named owner.

## Action points

1. Confirm with the owners of the UAE hosts whether those hosts are in scope
   for automation.
