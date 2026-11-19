# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Starts a Jenkins controller with the real module, plugin set, jobs and agents
# of a controller host, and checks that it works. Secrets, URLs and
# authentication providers are replaced with dummies. For the release
# controller the test also starts a release builder that trusts an SSH user CA.
# The test does not cover SSH host key verification.
{ self, host }:
let
  pkgs = self.inputs.nixpkgs.legacyPackages.x86_64-linux;
  inherit (pkgs) lib;
  controller = self.nixosConfigurations.${host}.config;
  real = controller.services.ghaf-jenkins;
  release = real.envType == "release";
  builder = lib.findFirst (m: m.system == "x86_64-linux") null controller.nix.buildMachines;
  builderHost = lib.optionalString release (lib.removeSuffix "?trusted=true" builder.hostName);
  jobs = lib.attrNames real.jobs;
  # The controllers of prod enable scheduled deployment, which adds a Jenkins script that holds the queue
  scheduled = controller.services.scheduled-deployment.enable or false;
  # A group of the real controller that may administer Jenkins
  admin = lib.findFirst (g: lib.elem "Overall/Administer" real.auth.groups.${g}) null (
    lib.attrNames real.auth.groups
  );
  secret = "${pkgs.writeText "dummy-secret" "dummy"}";
  ssh = pkgs.runCommand "release-builder-ssh" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir $out
    ssh-keygen -q -t ed25519 -N "" -f $out/ca
    ssh-keygen -q -t ed25519 -N "" -f $out/user
    ssh-keygen -q -s $out/ca -I test -n ${builder.sshUser} -V always:forever $out/user.pub
  '';
  brokenPipeline = pkgs.writeText "broken.groovy" "pipeline { agent any\n stages { stage('a') { bogus { } } } }\n";
in
pkgs.testers.runNixOSTest {
  name = "jenkins-controller-${host}";

  nodes = {
    controller = {
      imports = [
        self.nixosModules.jenkins
      ]
      ++ lib.optionals scheduled [
        self.nixosModules.scheduled-deployment
        { services.scheduled-deployment.enable = true; }
      ];
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
      services.ghaf-jenkins = {
        enable = true;
        inherit (real)
          envType
          sourceVsa
          provenanceTrustPolicyFile
          releasePolicyFile
          agents
          jobs
          remoteStores
          ;
        url = "http://controller";
        registry = {
          enable = true;
          url = "registry.invalid";
          passwordFile = secret;
        };
        auth = {
          enable = true;
          domain = "controller";
          clientID = "test";
          oidcIssuerUrl = "http://127.0.0.1:1";
          clientSecretFile = secret;
          cookieSecretFile = secret;
          inherit (real.auth) groups;
        };
        integrations =
          if release then
            {
              cachix = {
                enable = true;
                tokenFile = secret;
              };
            }
          else
            {
              github = {
                enable = true;
                tokenFile = secret;
                webhookSecretFile = secret;
              };
              jira = {
                enable = true;
                tokenFile = secret;
              };
            };
        archive = lib.mkIf release {
          enable = true;
          s3Credentials = {
            accessKeyFile = secret;
            secretKeyFile = secret;
          };
        };
      };

      # No login: the test sends the headers that oauth2-proxy would set.
      systemd.services.oauth2-proxy.wantedBy = lib.mkForce [ ];
      networking.firewall.allowedTCPPorts = [ 80 ];
      services.caddy.configFile = lib.mkForce (
        pkgs.writeText "Caddyfile" ''
          {
            admin off
            auto_https off
          }
          http://controller {
            reverse_proxy localhost:8081
          }
        ''
      );

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      programs.ssh.extraConfig = "StrictHostKeyChecking no";
      environment.systemPackages = [
        # curl as an admin; Jenkins wants a crumb with its session for POST
        (pkgs.writeShellScriptBin "jenkins" ''
          jar=$(mktemp)
          h="-H X-Forwarded-User:admin -H X-Forwarded-Groups:${admin}"
          crumb=$(${pkgs.curl}/bin/curl -sSf -b $jar -c $jar $h http://localhost:8081/crumbIssuer/api/json | ${pkgs.jq}/bin/jq -r .crumb)
          ${pkgs.curl}/bin/curl -sS --globoff -b $jar -c $jar $h -H "Jenkins-Crumb: $crumb" "$@"
        '')
      ];
    };
  }
  // lib.optionalAttrs release {
    ${builderHost} = {
      imports = [ self.nixosModules.remote-builder ];
      builder = {
        enable = true;
        inherit (builder) sshUser;
        sshTrustedCAFile = "${ssh}/ca.pub";
      };
      services.openssh.enable = true;
    };
  };

  testScript = ''
    import json

    start_all()
    controller.wait_for_unit("jenkins.service", timeout=300)
    controller.wait_until_succeeds("jenkins -f http://localhost:8081/api/json", timeout=300)

    with subtest("plugins"):
        groovy = "pm = jenkins.model.Jenkins.get().pluginManager; println groovy.json.JsonOutput.toJson([failed: pm.failedPlugins*.name, inactive: pm.plugins.findAll { !it.active }*.shortName, loaded: pm.plugins*.shortName])"
        plugins = json.loads(controller.succeed(f"jenkins http://localhost:8081/scriptText --data-urlencode 'script={groovy}'"))
        manifest = {p["name"] for p in json.load(open("${../modules/jenkins/plugins.json}"))}
        assert plugins["failed"] == [] and plugins["inactive"] == [], plugins
        assert manifest <= set(plugins["loaded"]), sorted(manifest - set(plugins["loaded"]))

    with subtest("authentication"):
        assert controller.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/api/json") == "403"
        controller.succeed("jenkins -f http://localhost:8081/api/json")

    with subtest("test agents"):
        # What a test agent does when it starts: fetch its connection secret
        nodes = json.loads(controller.succeed("jenkins -f 'http://localhost:8081/computer/api/json?tree=computer[displayName]'"))["computer"]
        agents = [n["displayName"] for n in nodes if n["displayName"] != "Built-In Node"]
        assert agents, nodes
        for agent in agents:
            controller.succeed(f"curl -f -H 'X-Forwarded-User: testagent' -H 'X-Forwarded-Groups: testagents' http://localhost:8081/computer/{agent}/jenkins-agent.jnlp | grep -q application-desc")

    with subtest("jobs and pipelines"):
        jobs = json.loads(controller.succeed("jenkins -f 'http://localhost:8081/api/json?tree=jobs[name]'"))["jobs"]
        assert sorted(j["name"] for j in jobs) == ${builtins.toJSON jobs}
        def lint(file):
            out = controller.succeed(f"jenkins http://localhost:8081/pipeline-model-converter/validateJenkinsfile --data-urlencode jenkinsfile@{file}")
            return json.loads(out)["data"]["result"]
        for job in ${builtins.toJSON jobs}:
            assert lint(f"${../modules/jenkins/pipelines}/{job}.groovy") == "success", job
        # The linter must reject a broken pipeline, or the checks above show nothing
        assert lint("${brokenPipeline}") == "failure"

    ${lib.optionalString release ''
      with subtest("release builder"):
          # What install-release provisions on the controller
          controller.succeed("install -d -m 0750 -o root -g jenkins $(dirname ${builder.sshKey})")
          controller.succeed("install -m 0400 -o jenkins ${ssh}/user ${builder.sshKey}")
          controller.succeed("install -m 0444 -o jenkins ${ssh}/user-cert.pub ${builder.sshKey}-cert.pub")
          ${lib.replaceStrings [ "-" ] [ "_" ] builderHost}.wait_for_unit("sshd.service")
          # What the release pipeline does as the jenkins user, with the store from remote-stores.json
          store = json.loads(controller.succeed("cat /etc/jenkins/remote-stores.json"))["x86_64-linux"]
          jenkins_nix = "cd /tmp && runuser -u jenkins -- env HOME=/var/lib/jenkins PATH=/run/current-system/sw/bin nix"
          assert json.loads(controller.succeed(f"{jenkins_nix} store info --json --store '{store}'"))["trusted"]
          expr = "derivation { name = \"remote\"; system = \"x86_64-linux\"; builder = \"/bin/sh\"; args = [ \"-c\" \"echo ok > $out\" ]; }"
          out = json.loads(controller.succeed(f"{jenkins_nix} build --store '{store}' --eval-store auto --json --no-link --impure --expr '{expr}'"))[0]["outputs"]["out"]
          ${lib.replaceStrings [ "-" ] [ "_" ] builderHost}.succeed(f"test -e {out}")
          controller.succeed(f"{jenkins_nix} copy --from '{store}' --no-check-sigs {out}")
    ''}
  '';
}
