<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scheduled deployment

Hosts that enable `services.scheduled-deployment`
([module](../modules/scheduled-deployment/)) deploy the head of `main` to
themselves once a week. Each host fetches the public repository and builds its
own configuration, so no deployer or deploy credential is involved.
[Test agents](#test-agents) take their Jenkins nodes offline during a
deployment. On [baseline reset](./baseline-reset.md) hosts, every deployment
[reboots](#how-a-run-works). Jenkins controllers and builders are not supported
yet.

## How a run works

A run is one start of the `scheduled-deployment` service, by its timer or
[by hand](#running-a-deployment-by-hand). The timer starts a run every 30
minutes in the host's window, by default Tuesday 05:00 to 08:30 UTC. A run
that deploys or finds the host up to date ends the window: runs in the next 24
hours exit without doing anything. A skipped or failed run leaves the window
open, so a fix or revert merged on `main` during the window is picked up.

Each run:

1. Fetches `main` from GitHub, without credentials, and pins its head as the
   target.
2. Holds if the running revision is not on `main`, or if the next-boot system
   is neither the running system nor the target. Skips if the target was
   rejected on this host before, or if less than 10 GiB is free for the build.
3. Builds the target on the host.
4. On a [test agent](#test-agents), takes the agent's nodes offline and waits
   up to an hour until no test runs on them.
5. Skips if a unit has failed, then switches to the target. If the kernel,
   initrd or kernel modules change, or a switch inhibitor refuses the switch,
   it makes the target the boot default and reboots instead. Baseline-reset
   hosts always take this reboot path, while still drained.
6. Checks that the running revision is the target, no unit has failed, `sshd`
   and Nebula are running, and the host's `postDeployChecks` pass. After a
   reboot, `scheduled-deployment-verify` runs the checks two minutes after
   boot.

If the checks fail after a switch, the host switches back to the previous
system and rejects the target. If they fail after a reboot, nothing is rolled
back, the target is rejected, and an administrator decides what to do. A
rejected target is not deployed on that host again.

On baseline-reset hosts, `/var/lib/scheduled-deployment` is a symlink to
`/var/lib/baseline-reset/scheduled-deployment`. The module keeps `pending`,
`succeeded` (including its last-success mtime), `rejected`, `hold` and
`scheduled.prom` across resets through `services.baseline-reset.persistentFiles`.
The verification service republishes the metrics in `/run` after boot. The Git
repository, build result and lock files are discarded at reset.

Logs are in the journal:

```sh
journalctl -u scheduled-deployment -u scheduled-deployment-verify
```

The last result of each host is shown in the "Scheduled deployments" table on
the [Deployment drift](https://monitoring.vedenemo.dev/d/ghaf-deployment-drift)
dashboard.

## Results

| Result | Reason | Meaning and action |
|---|---|---|
| `deployed` | `switch_verified`, `reboot_verified` | Deployed the target and the checks passed. |
| `up_to_date` | `already_running` | The host already runs the head of `main`. |
| `skipped` | `network_error` | Fetching `main` failed. The next run retries. |
| `skipped` | `build_failed` | The build failed, also when inputs or caches are unavailable. The next run retries. If it keeps failing, build the host locally to see the error. |
| `skipped` | `low_disk_space` | Less than 10 GiB is free in `/nix/store`. Free space on the host. |
| `skipped` | `drain_failed` | Taking a test agent's nodes offline failed. The nodes are back online, and the next run retries. |
| `skipped` | `drain_timeout` | Tests kept running on a test agent's nodes for an hour. The nodes are back online, and the next run retries. |
| `skipped` | `failed_units` | A unit had failed before activation. Fix the unit, or clear it with `systemctl reset-failed`. |
| `skipped` | `rejected_target` | The head of `main` failed on this host before. A new commit on `main` gets a new attempt; to retry the same commit, [clear the rejected target](#retrying-a-rejected-target). |
| `held` | `operator_hold` | Someone [paused the host](#pausing-a-host). |
| `held` | `running_branch` | The host runs a revision that is not on `main`, from a branch or a dirty checkout. See [manual deployments](#manual-deployments). |
| `held` | `staged_branch` | The next-boot system is neither the running system nor the target, for example after `deploy --boot` of a branch. Reboot into it, or deploy `main`. |
| `held` | `configuration_changed` | Someone deployed the host during the build. The next run retries. |
| `held` | `module_disabled` | The target disables scheduled deployment on this host. Deploy it manually. |
| `held` | `boot_verification_pending` | A reboot into the target has not been verified yet. `scheduled-deployment-verify` does that two minutes after boot; if it stays pending, check that service's journal and start it again. |
| `failed` | `activation_failed`, `post_switch_checks` | Activation or the checks after a switch failed. The host switched back to the previous system and rejected the target. Find the cause in the journal. |
| `failed` | `post_boot_checks` | The checks failed after the reboot, or the host did not boot the target. Nothing was rolled back, and the target is rejected. Check what the host runs, then fix it or deploy a working revision manually. |
| `failed` | `rollback_failed`, `unverified_activation` | Switching back failed, or an activation in the current boot was interrupted. Later runs report `unverified_activation` until an administrator checks what the host runs, fixes it and deletes `/var/lib/scheduled-deployment/pending`. The target, the first field in `pending`, is not rejected; to keep it from being retried, add it to `rejected` first. |
| `failed` | `drain_not_ended` | Bringing the test agent's nodes back online failed, for example because the controller is unreachable. If the run got as far as activation, the target is deployed and verified. [Bring the nodes online](#test-agents) in Jenkins. |

## Alerts

Grafana sends two alerts from the "Scheduled deployment" rule group to Slack:

- `scheduled deployment failed`: a host reported `failed`, or skipped a
  rejected target, after its last success.
- `scheduled deployment stalled`: a host's last successful run was more than
  15 days (two windows) ago. A host that has never succeeded alerts on its
  first run that does not succeed. The dashboard shows why, usually a forgotten
  hold or a held branch.

Both alerts clear when a run deploys or finds the host up to date. After
fixing the cause, [start a run](#running-a-deployment-by-hand) instead of
waiting for the next window; a host that runs the head of `main` then reports
`up_to_date`. A run skips a rejected target even when the host already runs
it, so after deploying a rejected target manually, also
[clear the record](#retrying-a-rejected-target).

## Running a deployment by hand

```sh
sudo systemctl start --no-block scheduled-deployment
journalctl -fu scheduled-deployment
```

A manual run works outside the window too, and reboots the host right away if
the deployment needs a reboot. Within 24 hours of a run that deployed or found
the host up to date, it exits without doing anything; delete
`/var/lib/scheduled-deployment/succeeded` first to run anyway. The same
applies to the window, so a successful run by hand on the day before the window
delays or skips it.

## Pausing a host

```sh
sudo scheduled-deployment hold "replacing a disk"
sudo scheduled-deployment release
```

The hold records the user, the time and the reason in
`/var/lib/scheduled-deployment/hold`. A run in progress stops before it
activates the target. A run that is waiting for a test agent's nodes stops
within 30 seconds. If activation has already started, the hold command waits
until the run finishes. Releasing does not start a run. A held host reports
`held operator_hold`, and `scheduled deployment stalled` fires after 15 days
without a success, so a forgotten hold is noticed.

To stop a bad commit from reaching more hosts, fix or revert it on `main`. A
run in progress keeps its target, so also hold the hosts where a run is in
progress. To stop automation for longer, [remove the host](#removing-a-host).

## Manual deployments

[deploy-rs](./deploy-rs.md) works as before on enrolled hosts. Deploy from a
clean checkout of `main`. A host that runs a revision that is not on `main`,
from a branch or a dirty tree, holds with `running_branch` until `main`
contains that revision or is deployed to it again. Rebase and squash merges
create new commits, so a branch deployed for testing is not on `main` even
after its pull request merges; deploy `main` again after merging.

A change that must reach several hosts together, for example matching secrets
or keys, is deployed manually to all of them right after merging. The
automation then finds them up to date.

## Retrying a rejected target

Rejected targets are listed, one revision per line, in
`/var/lib/scheduled-deployment/rejected`. Delete the line, or the file, and
[start a run](#running-a-deployment-by-hand) to retry.

## Test agents

On a [test agent](./jenkins-testagents.md), a run takes the agent's nodes
temporarily offline on its controller, with the message "Scheduled deployment
of <host>", and waits until they are idle. Nodes that are already offline for
another reason are left as they are. While the nodes are offline, HW test runs
that already wait for a node keep waiting, and a new run fails with "No test
agents online" if no other node for its device is online. An agent that is not
connected to a controller is deployed without taking nodes offline.

If the run stops before activation, for example on a hold, it brings the
nodes back online right away. After activation, they come back online once the target is verified, after the
switch or after the reboot; the agents reconnect after a reboot. The checks
wait up to two minutes for each agent to connect to the controller. After a
`failed` result, the nodes stay offline until a later run ends its own drain,
or until someone brings them back online in Jenkins: once the host is fixed,
open the node's page and select "Bring this node back online".

## Enrolling a host

1. The host must expose metrics (`services.monitoring.metrics.enable`) and be
   scraped by Prometheus, see [monitoring](./monitoring.md#hosts). Otherwise a
   failure raises no alert.
2. Import `scheduled-deployment` from `self.nixosModules`, enable it and add
   checks for the host's own services, retrying while the services restarted
   by a switch start up. For example, see
   [ghaf-log](../hosts/ghaf-log/configuration.nix):

   ```nix
   services.scheduled-deployment = {
     enable = true;
     postDeployChecks = ''
       ${lib.getExe pkgs.curl} -fsS --retry 10 --retry-delay 6 --retry-all-errors http://127.0.0.1:3100/ready
     '';
   };
   ```

   `window` sets a different systemd `OnCalendar` window. On a test agent,
   enabling the module is enough: the test agent configuration adds the
   [drain and the checks](#test-agents). Its controller must run a revision of
   `main` that gives test agents the `Agent/Disconnect` permission.
3. After merging, deploy `main` to the host from a clean checkout, and
   optionally [run it by hand](#running-a-deployment-by-hand) to see
   `up_to_date`.

## Removing a host

Disable the module in the host's configuration and deploy it manually; runs
hold a target that disables the module (`module_disabled`). Then delete
`/run/ghaf-deployment-metrics/scheduled.prom`, or reboot the host. Otherwise
node-exporter keeps exporting the last result, and
`scheduled deployment stalled` fires once the last success is 15 days old. If
the last result was a failure, `scheduled deployment failed` can keep firing
for up to 15 days: silence it in Grafana. `/var/lib/scheduled-deployment` can
be deleted.
