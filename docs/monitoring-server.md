<!--
SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Monitoring server

Monitoring server is running Grafana on port 80 and Prometheus on port 9090.

It's configuration is located in `hosts/monitoring`.

## Adding metrics endpoint

### ubuntu host

```sh
sudo apt-get install prometheus-node-exporter
sudo systemctl enable prometheus-node-exporter.service
sudo systemctl start prometheus-node-exporter.service
```

Metrics should now be available at `127.0.0.1:9100/metrics`

```sh
curl 127.0.0.1:9100/metrics
```

If metrics are not accessible from another machine in ficolo network, check firewall:

```sh
sudo ufw status
sudo ufw allow 9100/tcp
```
### nixos host

For a host managed by this repo, simply import `service-node-exporter`

## Authentication

### ubuntu host

For http basic auth, it is easiest to use nginx.

Create password file

```sh
sudo apt-get install apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd scraper
```

And add this to the nginx config of your server:

```
location /metrics {
    proxy_pass http://127.0.0.1:9100/metrics;

    auth_basic           "Verify yourself!";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
```

### nixos host

- Add metrics htpasswd to secrets.yaml
- Add authenticated nginx location with htpasswd file from secrets

```nix
locations."/metrics" = {
  proxyPass = "http://127.0.0.1:${toString config.services.prometheus.exporters.node.port}/metrics";
  basicAuthFile = config.sops.secrets.metrics-htpasswd.path;
};
```

### prometheus side

For prometheus to use this username and password when scraping, an authenticated job must be added:

```nix
sops.secrets.metrics-password.owner = "prometheus";
...
{
  job_name = "authenticated";
  scheme = "https";
  basic_auth = {
    username = "scraper";
    password_file = config.sops.secrets.metrics-password.path;
  };
  static_configs = [
    {
      targets = [
        "mytarget"
      ];
    }
  ];
}
```

### Using ssh proxy

When webserver is not desired, or ports 80 and 443 are not available, metrics can be scraped through ssh.
This is not natively supported by prometheus, but a proxy server like [sshified](https://github.com/hoffie/sshified) can be used.

```sh
./sshified --proxy.listen-addr 127.0.0.1:8888 \
  --ssh.user sshified \
  --ssh.key-file ~/.ssh/id_ed25519 \
  --ssh.known-hosts-file ~/.ssh/known_hosts \
  --ssh.port 22 -v
```

This has been set up in monitoring server as a systemd service.

Remote server has to be set up to allow ssh access for user `sshified` with the given ssh key.

Prometheus can then be set up to scrape the remote server with `127.0.0.1:8888` as the proxy.

The ssh proxy will redirect the request to remote server's `127.0.0.1:9100`.

## Reading metrics

In the monitoring server, there is prometheus instance that is scraping all targets.
Adding a metrics target is simple.

```diff
services.prometheus.scrapeConfigs = [
  {
    ...
    static_configs = [
      {
        targets = [
          "ganymede.vedenemo.dev"
+         "mytarget.com"
        ];
      }
    ];
  }
];
```

By default prometheus will search for metrics in the given target at `/metrics`
