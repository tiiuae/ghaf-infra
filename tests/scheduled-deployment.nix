# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ nixpkgs }:
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  fixtureFlake = pkgs.writeText "flake.nix" ''
    {
      inputs.nixpkgs.url = "path:${nixpkgs}";
      outputs = { self, nixpkgs }: {
        nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
          specialArgs = {
            testRevision = self.rev;
            testVariant = builtins.readFile ./generation;
          };
          modules = [ ./tests/scheduled-deployment-machine.nix ];
        };
      };
    }
  '';
  repository =
    pkgs.runCommand "scheduled-deployment-repository"
      {
        nativeBuildInputs = [
          pkgs.gitMinimal
          pkgs.jq
        ];
      }
      ''
        mkdir -p $out/tests $out/modules
        cd $out
        cp ${fixtureFlake} flake.nix
        cp ${./scheduled-deployment-machine.nix} tests/scheduled-deployment-machine.nix
        cp -r ${../modules/scheduled-deployment} modules/scheduled-deployment
        cp ${../modules/monitoring.nix} modules/monitoring.nix
        git init -b main
        git config user.name Test
        git config user.email test@example.invalid
        export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
        printf base > generation
        git add .
        git commit -m base
        base=$(git rev-parse HEAD)
        printf good > generation
        git commit -am good
        good=$(git rev-parse HEAD)
        printf bad > generation
        git commit -am bad
        bad=$(git rev-parse HEAD)
        printf reboot > generation
        git commit -am reboot
        reboot=$(git rev-parse HEAD)
        jq -n --arg base "$base" --arg good "$good" --arg bad "$bad" --arg reboot "$reboot" \
          '{base: $base, good: $good, bad: $bad, reboot: $reboot}' > revisions.json
      '';
  # IFD is confined to this opt-in output. Known commit IDs let us prebuild the
  # exact systems that the VM's local flake evaluates, without network access.
  revisions = builtins.fromJSON (builtins.readFile "${repository}/revisions.json");
  systems = lib.genAttrs [ "base" "good" "bad" "reboot" ] (
    variant:
    (nixpkgs.lib.nixosSystem {
      specialArgs = {
        testRevision = revisions.${variant};
        testVariant = variant;
      };
      modules = [ ./scheduled-deployment-machine.nix ];
    }).config.system.build.toplevel
  );
in
pkgs.testers.runNixOSTest {
  name = "scheduled-deployment";
  node.pkgsReadOnly = false;
  node.specialArgs = {
    testRevision = revisions.base;
    testVariant = "base";
  };
  nodes.machine = {
    imports = [ ./scheduled-deployment-machine.nix ];
    virtualisation.additionalPaths = [
      nixpkgs
      repository
    ]
    ++ builtins.attrValues systems;
  };
  testScript = ''
    import re

    machine.start()
    machine.wait_for_unit("multi-user.target")
    # Start the sequence from the standalone baseline, without the test
    # framework's extra initrd settings. All deployments then use real systems
    # built by the same local flake.
    machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${systems.base}; ${systems.base}/bin/switch-to-configuration boot")
    machine.execute("systemctl reboot")
    machine.wait_for_shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("cp -r ${repository} /repo; chmod -R u+w /repo")
    state = "/var/lib/scheduled-deployment"

    def result():
        metrics = machine.succeed("cat /run/ghaf-deployment-metrics/scheduled.prom")
        return re.findall(r'result="(\w+)",reason="(\w+)",target="(\w*)"', metrics)[0]

    def run():
        machine.succeed("systemctl start scheduled-deployment.service")
        return result()

    def next_window():
        machine.succeed(f"rm {state}/succeeded")

    def revision():
        return machine.succeed("nixos-version --configuration-revision").strip()

    with subtest("switch and one deployment per window"):
        machine.succeed("git -C /repo update-ref refs/heads/main ${revisions.good}")
        boot_id = machine.succeed("cat /proc/sys/kernel/random/boot_id")
        assert run() == ("deployed", "switch_verified", "${revisions.good}")
        assert revision() == "${revisions.good}"
        machine.succeed("test ! -e /var/lib/drained")
        assert machine.succeed("cat /proc/sys/kernel/random/boot_id") == boot_id
        machine.succeed("git -C /repo update-ref refs/heads/main ${revisions.bad}")
        assert run() == ("deployed", "switch_verified", "${revisions.good}")
        assert revision() == "${revisions.good}"

    with subtest("operator hold, running revision ahead of main and staged branch hold deployment"):
        next_window()
        machine.succeed("scheduled-deployment hold testing")
        assert run()[:2] == ("held", "operator_hold")
        machine.succeed("scheduled-deployment release")
        machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${systems.reboot}; ${systems.reboot}/bin/switch-to-configuration switch")
        assert run()[:2] == ("held", "running_branch")
        assert revision() == "${revisions.reboot}"
        machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${systems.good}; ${systems.good}/bin/switch-to-configuration switch")
        machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${systems.reboot}; ${systems.reboot}/bin/switch-to-configuration boot")
        assert run()[:2] == ("held", "staged_branch")
        assert machine.succeed("readlink -e /nix/var/nix/profiles/system").strip() == "${systems.reboot}"
        machine.succeed("nix-env -p /nix/var/nix/profiles/system --set ${systems.good}; ${systems.good}/bin/switch-to-configuration boot")

    with subtest("failed check rolls back and rejects target"):
        assert run() == ("failed", "post_switch_checks", "${revisions.bad}")
        assert revision() == "${revisions.good}"
        machine.succeed(f"grep -Fx ${revisions.bad} {state}/rejected; test ! -e {state}/pending")
        machine.succeed("test -e /var/lib/drained")
        # A failed attempt leaves the window open.
        assert run()[:2] == ("skipped", "rejected_target")
        assert revision() == "${revisions.good}"
        # An administrator ends the drain after a failure.
        machine.succeed("rm /var/lib/drained")

    with subtest("hold during the drain ends it"):
        machine.succeed("git -C /repo update-ref refs/heads/main ${revisions.reboot}")
        machine.succeed("touch /var/lib/busy; systemctl start --no-block scheduled-deployment.service")
        machine.wait_until_succeeds("test -e /var/lib/drained")
        machine.succeed("scheduled-deployment hold testing")
        machine.wait_until_succeeds("test $(systemctl show -P ActiveState scheduled-deployment.service) = inactive")
        machine.succeed("test ! -e /var/lib/drained")
        assert result()[:2] == ("held", "operator_hold")
        assert revision() == "${revisions.good}"
        machine.succeed("scheduled-deployment release; rm /var/lib/busy")

    with subtest("initrd change reboots and verifies"):
        machine.succeed("git -C /repo update-ref refs/heads/main ${revisions.reboot}")
        machine.succeed("systemctl start --no-block scheduled-deployment.service")
        machine.wait_for_shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_until_succeeds(f"test ! -e {state}/pending")
        assert result() == ("deployed", "reboot_verified", "${revisions.reboot}")
        assert revision() == "${revisions.reboot}"
        machine.succeed("test ! -e /var/lib/drained")
        assert machine.succeed("cat /proc/sys/kernel/random/boot_id") != boot_id
  '';
}
