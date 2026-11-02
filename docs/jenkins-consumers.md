<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Standalone Jenkins consumers

Import `nixosModules.jenkins` and `nixosModules.testagent` into your own host
configurations. Keep hardware, disks, users, secret provisioning and trust
policy in the consumer. These modules do not require importing a production host
or the Ghaf host inventory.

Scheduled deployment is separate. Neither role module imports it or
baseline-reset. To use it, explicitly import `nixosModules.scheduled-deployment`
and enable `services.scheduled-deployment` in the host. The role modules then
activate their drain and post-deployment checks.
Downstream hosts must also set its `repository` to their own infrastructure
repository.

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
`services.testagent`. Interchangeable agents may share identical node definitions;
those are registered once. Conflicting definitions with the same name are
rejected. Nodes retain device and `<variant>-<device>` labels for pipeline selection.
Legacy `nodes.devices`, `nodes.testagentHosts`, and
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

Use the `devices` list to select Jenkins device nodes. Keep SSD
symlinks, USB hub settings and other hardware-specific udev rules in the host
configuration, alongside its JSON. There is no separate device schema.

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
`test-server-pass`, `fleetdm_enroll_secret`, and `fleetdm_api_token`.
The host supplies the credentials needed by its Robot
suites; the module does not validate or infer them from the hardware
configuration.

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
at Robot's expected locations inside each agent service.
`controllerSshKeyFile` defaults to the separate `ssh_host_ed25519_key` secret;
the policy defaults to the repository policy. Both can be overridden by consumers.

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
