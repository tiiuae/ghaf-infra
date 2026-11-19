# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Checks node metrics and journal logs from the real monitoring module against
# the ghaf-monitoring Prometheus and Loki settings. Uses test TLS and credentials;
# dashboards and alerts are not covered.
{ self }:
let
  pkgs = self.inputs.nixpkgs.legacyPackages.x86_64-linux;
  real = self.nixosConfigurations.ghaf-monitoring.config;
  prometheus = real.services.prometheus;
  loki = real.services.loki;
  tls =
    pkgs.runCommand "monitoring-test-tls"
      {
        nativeBuildInputs = [
          pkgs.openssl
          pkgs.apacheHttpd
        ];
      }
      ''
        mkdir $out
        openssl req -x509 -newkey rsa:2048 -nodes -keyout $out/key.pem -out $out/cert.pem -days 36500 \
          -subj /CN=monitoring.vedenemo.dev -addext subjectAltName=DNS:monitoring.vedenemo.dev
        htpasswd -nbm logger testpass > $out/htpasswd
      '';
in
pkgs.testers.runNixOSTest {
  name = "monitoring";

  nodes.monitor = {
    services.prometheus = {
      enable = true;
      inherit (prometheus)
        port
        listenAddress
        webExternalUrl
        extraFlags
        globalConfig
        ;
    };
    services.loki = {
      enable = true;
      inherit (loki) dataDir configuration;
    };
    systemd.tmpfiles.rules = [ "d ${loki.dataDir} 0750 loki loki - -" ];
    # The agent pushes metrics and logs to this HTTPS endpoint with basic auth, as to ghaf-monitoring.
    services.nginx = {
      enable = true;
      virtualHosts."monitoring.vedenemo.dev" = {
        onlySSL = true;
        sslCertificate = "${tls}/cert.pem";
        sslCertificateKey = "${tls}/key.pem";
        locations =
          pkgs.lib.genAttrs
            [
              "/prometheus/"
              "/loki"
            ]
            (path: {
              inherit (real.services.nginx.virtualHosts."monitoring.vedenemo.dev".locations.${path}) proxyPass;
              basicAuthFile = "${tls}/htpasswd";
            });
      };
    };
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
  nodes.agent =
    { nodes, ... }:
    {
      imports = [ self.nixosModules.monitoring ];
      networking.hostName = "agent-under-test";
      networking.extraHosts = "${nodes.monitor.networking.primaryIPAddress} monitoring.vedenemo.dev";
      security.pki.certificateFiles = [ "${tls}/cert.pem" ];
      services.monitoring = {
        metrics = {
          enable = true;
          push = true;
        };
        logs = {
          enable = true;
          lokiAddress = "https://monitoring.vedenemo.dev";
          auth.password_file = "/run/metrics_password";
        };
      };
      systemd.tmpfiles.rules = [ "f+ /run/metrics_password 0400 alloy alloy - testpass" ];
    };

  testScript = ''
    import json

    def query(command):
        # Prometheus and Loki are active before their HTTP APIs answer
        status, out = monitor.execute(command)
        return status == 0 and json.loads(out)["data"]["result"]

    start_all()
    monitor.wait_for_unit("prometheus.service")
    monitor.wait_for_unit("loki.service")
    monitor.wait_for_unit("nginx.service")
    agent.wait_for_unit("alloy.service")

    with subtest("metrics"):
        retry(
            lambda _: query(
                """curl -fsSG http://${prometheus.listenAddress}:${toString prometheus.port}${prometheus.webExternalUrl}api/v1/query """
                """--data-urlencode 'query=node_uname_info{job="push",instance="agent-under-test",nodename="agent-under-test"}'"""
            ),
            timeout_seconds=180,
        )

    with subtest("journal logs"):
        agent.succeed("systemd-cat -t monitoring-test echo MONITORING-JOURNAL-MARKER")
        retry(
            lambda _: query(
                """curl -fsSG http://127.0.0.1:${toString loki.configuration.server.http_listen_port}/loki/api/v1/query_range """
                """--data-urlencode 'query={job="systemd-journal",host="agent-under-test"} |= "MONITORING-JOURNAL-MARKER"'"""
            ),
            timeout_seconds=180,
        )
  '';
}
