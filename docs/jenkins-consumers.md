<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Standalone Jenkins consumers

Import `nixosModules.jenkins` and `nixosModules.testagent` into your own host
configurations. Keep hardware, disks, users, secret provisioning and trust
policy in the consumer. These modules do not require importing a production host
or the Ghaf host inventory.

Hetzner consumers can import `nixosModules.hetzner-cloud` or
`nixosModules.hetzner-robot` directly without a `machines` argument, SOPS or the
monitoring module. The monitoring module uses the private Loki endpoint for
inventory hosts with an internal IP and the public endpoint for other hosts.
Standalone users set `services.monitoring.logs.lokiAddress` explicitly. For the
public Ghaf endpoint, a declared SOPS `loki_password` secret supplies the
default password file; hosts own its declaration and permissions.
`nixosModules.azure` provides the guest profile, EFI tooling, a redistributable
firmware default, Azure agent, cloud-init, networking and Hyper-V drivers. It
requires neither inventory nor monitoring; consumers do not need an additional
`qemu-guest.nix` import or `efibootmgr` package declaration. Disk layout and
bootloader selection remain host configuration, as do Nix tuning and sudo policy.

Scheduled deployment is separate. Neither role module imports it or
baseline-reset. To use it, explicitly import `nixosModules.scheduled-deployment`
and enable `services.scheduled-deployment` in the host. The role modules then
activate their drain and post-deployment checks. Downstream hosts must also set
its `repository` to their own infrastructure repository.

## Shared Nix settings

Import `ghaf-infra.nixosModules.nix-settings` for shared Nix defaults, including
the `nix.caches` option:

```nix
{
  imports = [ ghaf-infra.nixosModules.nix-settings ];

  nix.caches = [ "nixos-org" "ghaf-dev" ];
  nix.gc = {
    automatic = true;
    dates = "daily";
    keepSystemGenerations = 3;
  };
  nix.settings = {
    min-free = 10 * 1024 * 1024 * 1024;
    max-free = 40 * 1024 * 1024 * 1024;
  };
}
```

The module enables flakes and the Nix command, lets remote builders use
substitutes, and supplies overridable daemon scheduling and OOM-score defaults.
It trusts `root` and `@wheel`; service modules can add their own trusted users.
Use `nix.settings.trusted-users = lib.mkForce [ "root" ];` for a restricted list.

`nix.gc.automatic` enables scheduled garbage collection, system-profile pruning,
disk-pressure GC defaults and GC retries on failure together. It defaults to
`false` for standalone consumers. Pruning runs before collection in the same
service, keeping `nix.gc.keepSystemGenerations` generations (default 3).
`nix.gc.dates`, `options`, `randomizedDelaySec`, and `persistent` retain their
native NixOS meanings. Age-based deletion in `options` may remove additional
generations. The default free-space thresholds are 20 GiB and 200 GiB; choose
values appropriate to the host's disk.

`nix.caches` defaults to `[ "nixos-org" ]`. Available names are `nixos-org`,
`ghaf-dev`, `ghaf-dbg`, and `ghaf-release`. An empty list adds no named caches;
normal NixOS cache defaults still apply. Add custom caches through native
`nix.settings.substituters` and `nix.settings.trusted-public-keys`.

This module needs no `self`, `inputs`, or inventory arguments and imports no
monitoring or secret provisioning. Hosts own unfree-package policy,
boot configuration and deployment policy. Set `system.configurationRevision`,
`nix.registry`, and `nix.nixPath` explicitly using the consumer's own flake when
needed. The existing `common` module imports `nix-settings`, opts into automatic
GC by default, and retains Ghaf's cache selection and other site policy. Its
former separate profile-pruning timer is replaced by pruning before GC.

## Controller jobs and agent registrations

```nix
services.ghaf-jenkins = {
  enable = true;
  envType = "dev";
  url = "https://jenkins.example.org";
  provenanceTrustPolicyFile = ./provenance.yaml;
  releasePolicyFile = ./release.yaml;

  jobs.build = {
    scriptFile = ./build.groovy;
    description = "Build local targets through the ghafInfra library";
  };
  jobs.ghaf-hw-test = { };
  agents.lab = {
    hostName = "lab-agent";
    publicKey = "ssh-ed25519 ...";
    variant = "dev";
    devices = [ "lenovo-x1" ];
  };
};
```

All pipelines are declared through `jobs`. `scriptFile` defaults to the bundled
`pipelines/<job-name>.groovy`; set it explicitly for a consumer-owned script.
For example, `jobs.ghaf-hw-test = { };` loads the bundled hardware test
pipeline. The script is copied unchanged and loaded as a sandboxed Pipeline
definition. Dollar signs and Groovy interpolation need no extra escaping. Job
names must be flat names containing letters, digits, underscores, dots or
hyphens.

Each `agents` entry declares its device nodes and SSH account. Set
`enable = false` for an unprovisioned registration. Enabled entries require a
public key. Node names default to `<variant>-<device>`. When two agents share a
variant and device label, give each a unique `nodeNamePrefix` if they need to
connect to the same controller simultaneously. Configure the same prefix in its
`services.testagent`. Interchangeable agents may share identical node
definitions; those are registered once. Conflicting definitions with the same
name are rejected. Nodes retain device and `<variant>-<device>` labels for
pipeline selection. Legacy `nodes.devices`, `nodes.testagentHosts`, and
`nodes.authorizedKeys` remain supported.

Jobs default to `reloadOnStartup = true`, invoking them with `RELOAD_ONLY=true`
after Jenkins starts. Disable this for a job that should not run at startup:

```nix
services.ghaf-jenkins.jobs.build.reloadOnStartup = false;
```

The script must handle that parameter by refreshing its parameters and returning
without building. Only jobs with startup reload enabled are scheduled; arbitrary
Jenkins jobs are never discovered and scheduled. Existing controllers retain
their startup reloads through this per-job setting. On every boot, Jenkins
configuration is reset before Configuration as Code recreates it. Cleanup
deletes root XML files, node definitions and top-level job config files. Declare
configuration in Nix and Configuration as Code; changes made only through the
Jenkins UI do not persist across boots.

## Publishing and target selection

`services.ghaf-jenkins.registry.namespace` defaults to `"ghaf"`. OCI images use
`<namespace>/<job-name>/<target>`, keeping the job name unchanged and removing
the target's `packages.` prefix. Job names must be valid lowercase OCI
repository components when publishing.

Set `services.ghaf-jenkins.provenanceRepository` to the consumer's
infrastructure repository. It defaults to `https://github.com/tiiuae/ghaf-infra`
and changes `externalParameters.workflow.repository` in provenance. The build
target's repository and the provenance build-type URI keep their own identities.

Consumer pipelines can select a device directly in a target map:

```groovy
def targets = [
  [
    target: 'packages.aarch64-linux.delivery-orinnx-lab',
    device_tag: 'orin-nx',
    test_tags: [
      'orin-nxANDrelayboot',
      'orin-nxANDark',
    ],
    sbom: true,
  ],
]

pipelineExecution.create_pipeline(targets)
```

The optional `device_tag` supplies the default device for the target's tests and
is forwarded as `DEVICE_TAG` to the hardware job. It uses the existing device
labels, such as `orin-nx`, rather than matching the build target's name. A
device explicitly selected in an individual `tests` entry takes precedence.
Omitting the field preserves the existing inference and per-test configuration.

`test_tags` is an ordered list of complete Robot include-tag expressions. The
list runs in one hardware-test job, on one allocated agent, with one Robot
invocation per expression. The example runs `orin-nxANDrelayboot` followed by
`orin-nxANDark`. Expressions are passed unchanged and quoted; device filtering
belongs in the expression, while `device_tag` selects the Jenkins agent.

Boot handling matches the manual hardware-test job. There is no implicit boot
test: include a boot expression explicitly when needed. If an expression
containing `boot` fails, subsequent expressions are marked skipped. Other
failures mark the job failed while allowing later expressions to run. Each
invocation saves its outputs in `test-1`, `test-2`, and so on, and all results
are archived together.

Use either `test_tags` or the legacy `testset` selector. An empty list schedules
no tests. Each explicit `tests` entry can also provide its own `test_tags` list.
Existing `testset` callers retain their predefined stages and boot gating. The
automatic hardware job receives the list as a JSON `TEST_TAGS` parameter, which
takes precedence over `TESTSET`; the manual job's existing free-form `TEST_TAGS`
parameter is unchanged.

The optional `create_pipeline` options map accepts `hw_test_params`, a map of
additional string parameters forwarded to hardware jobs. For example:

```groovy
pipelineExecution.create_pipeline(targets, null, null, [
  hw_test_params: [
    GHAF_FLAKE_REF: 'github:tiiuae/ghaf/<pinned-commit>',
    CI_TEST_REPO_URL: 'https://github.com/tiiuae/ci-test-automation-ghaf-robots.git',
    CI_TEST_REPO_BRANCH: 'main',
  ],
])
```

This allows an image from a downstream repository to use a public pinned Ghaf
flash script. Test selection belongs in the target's `test_tags` or legacy
`testset` field; empty extra parameter values are omitted.

## Background Git authentication

Both role modules provide `programs.git.credentials`. Configure it on every
controller or agent that clones private repositories:

```nix
programs.git.credentials."https://github.com/tiiuae" = {
  username = "x-access-token";
  passwordFile = config.sops.secrets.github-token.path;
};

sops.secrets.github-token = {
  owner = "jenkins";
  mode = "0400";
};
```

Entries are keyed by HTTPS credential-context URLs, so credentials can be scoped
to a host or repository path. Git reads the configured runtime file through a
credential helper; tokens never enter the Nix store or checkout URLs. An
unreadable or missing file supplies no credentials. Provisioning and ownership
remain the host's responsibility.

Normal Git clone, fetch and ref-discovery commands use the helper automatically,
including Jenkins's default command-line Git backend. No per-checkout
`credentialsId` or private-repository branch workaround is required. JGit uses a
different backend; keep the default CLI implementation for this setup.
Matching host credentials take precedence over Jenkins job credentials. A host
token without access to the repository can block checkout even when the job's
own token has access. Scope the credential-context URLs narrowly or grant the
host token access to all repositories matching those URLs.
Credentials are available to any job or process that can read their runtime
file. Nix's `github:` fetcher uses its own access-token configuration; this
option configures Git HTTPS authentication.

## Agent hardware and runtime files

```nix
services.testagent = {
  enable = true;
  variant = "dev";
  devices = [ "lenovo-x1" ];
  controllerSshKeyFile = config.sops.secrets.agent-ssh-key.path;
  testCredentialFiles = {
    dut-pass = config.sops.secrets.dut-pass.path;
    switch-token = config.sops.secrets.switch-token.path;
    switch-secret = config.sops.secrets.switch-secret.path;
  };
  provenanceTrustPolicyFile = ./provenance.yaml;
  tooling.usbSdmux.enable = false;
};

sops.secrets = lib.genAttrs [ "agent-ssh-key" "dut-pass" "switch-token" "switch-secret" ] (_: {
  owner = "jenkins";
  mode = "0400";
  restartUnits = [ "start-agents.service" ];
});

services.testagent.testConfig = {
  addresses = {
    relay_serial_port = "NONE";
    LenovoX1-1 = {
      location = config.networking.hostName;
      device_id = "your-dut-id";
      netvm_hostname = "ghaf-your-device";
      device_ip_address = "192.0.2.10";
      ext_drive_by-id = "/dev/ssdX1";
      usbhub_serial = "YOUR_ACRONAME_HUB";
      switch_bot = "your-power-switch";
      threads = 20;
    };
  };
};
```

Use the `devices` list to select Jenkins device nodes. Keep SSD symlinks, USB
hub settings and other hardware-specific udev rules in the host configuration,
alongside its JSON. There is no separate device schema.

`testConfig` accepts arbitrary JSON content and writes it unchanged to
`/etc/jenkins/test_config.json`. No fields or defaults are added. It defaults to
`null`, which leaves the file unmanaged; existing hosts can continue defining
`environment.etc."jenkins/test_config.json"` directly.

Import sops-nix alongside the agent module and configure its encrypted secret
file and decryption identity in the host. Robot reads credentials directly from
`/run/secrets/<credential-name>`. Set `owner = "jenkins"`, `mode = "0400"`, and
`restartUnits = [ "start-agents.service" ]` on each agent secret. An SSH client
key is independent of the machine's SSH server host key and its age identity.

Only supply credentials for the peripherals in use. Robot uses names such as
`dut-pass`, `plug-login`, `plug-pass`, `switch-token`, `switch-secret`,
`wifi-ssid`, `wifi-password`, `pi-login`, `pi-pass`, `test-server-login`,
`test-server-pass`, `fleetdm_enroll_secret`, and `fleetdm_api_token`. The host
supplies the credentials needed by its Robot suites; the module does not
validate or infer them from the hardware configuration.

`testCredentialFiles` maps credential names to decrypted runtime files:

```nix
services.testagent.testCredentialFiles = {
  dut-pass = config.sops.secrets.dut-pass.path;
  fleetdm_enroll_secret = config.sops.secrets.fleetdm_enroll_secret.path;
  fleetdm_api_token = config.sops.secrets.fleetdm_api_token.path;
};
```

It defaults to an empty attribute set; configure only the credentials in use.
Hosts declare and decrypt their SOPS secrets. The module never reads their
contents during evaluation or adds secrets to SOPS itself. Standard
`/run/secrets/<name>` paths are used directly. Other paths are exposed read-only
at Robot's expected locations inside each agent service. `controllerSshKeyFile`
defaults to the separate `ssh_host_ed25519_key` secret; the policy defaults to
the repository policy. Both can be overridden by consumers.

Jetson tooling is enabled for Orin labels. BrainStem and USB SD mux tooling
remain enabled by default; KMTronic is installed with `tooling.relayboard`.
Enable the coupled tooling and exporter flag only when the test configuration
specifies a relay serial port; leave it disabled when the port is `"NONE"`.
Override these defaults with `tooling.jetson.enable`,
`tooling.brainstem.enable`, and `tooling.usbSdmux.enable`. `extraPackages` adds
tools to user sessions and agent services.

## Moving agents between controllers

The controller connection remains mutable. Run these commands on the agent:

```sh
connect https://controller-one.example.org
connect https://controller-two.example.org
disconnect
```

Enrollment removes the selected controller's saved key from the Jenkins user's
known-hosts file and connects with `StrictHostKeyChecking=no`, allowing the key
to be replaced when the controller is reinstalled. Configure other SSH behavior
through the host's normal SSH configuration.

Each controller must authorize the agent's public key and declare matching node
names. `connect` updates the runtime environment and restarts the agent
services. No NixOS rebuild or fixed controller URL is required. Network access
to the selected controller on SSH and HTTPS is required.
