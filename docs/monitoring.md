<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Monitoring

Grafana instance is publicly accessible at <https://monitoring.vedenemo.dev>.
The authentication happens through Github login. Login is accepted if you are
part of the `tiiuae` or and `devenv-fi` team.

The hosts in ghaf-infra are monitored with Grafana running on `ghaf-monitoring`.

Each host runs `node-exporter` to expose resource usage metrics, and optionally
sends systemd logs to loki.

The monitoring server has an additional Hetzner volume attached which stores the
state (metrics and logs) of Grafana, Prometheus & Loki.

## Hosts

### Hetzner Cloud

Hetzner cloud hosts are monitored through the Hetzner internal network. They
don't need authentication and are configured to scrape the metrics from
port 9100. They are configured in the `hetzner-cloud` prometheus scraping job.

### Hetzner Robot

Hetzner robot side machines cannot join the internal network the same way cloud
machines can. For this reason, they are monitored through an ssh proxy
(`sshified`). The scrape job `hetzner-robot` sends its traffic through this
proxy to the needed hosts.

### On-prem

Servers in the office are monitored through a nebula tunnel. These hosts must
join the nebula network, and be accessible under the `sumu.vedenemo.dev`
subdomain. Configured under the `office` scrape job.

#### relay-board

Test agents also expose the relay board statuses under port 8000, by running
`relay_board_exporter.py`. this is then scraped by the `relay-board` job.

#### NetHSM

`nethsm-gateway` is running `nethsm-exporter`, which exposes nethsm metrics
scraped from the NetHSM rest API. These metrics are scraped into the `nethsm`
job.

The gateway also sends the NetHSM logs in addition to systemd logs to loki.

## Development

A lot of the monitoring config depends on the host data in `hosts/machines.nix`
to be present.

To debug the prometheus jobs, visit <https://monitoring.vedenemo.dev/prometheus>
with basic auth credentials that you can find in the `secrets.yaml` under
`hosts/ghaf-monitoring`.

Everything in grafana is provisioned through the nix configuration. You cannot
manually edit alerts, dashboards or anything else. These are stored as JSON
under `provision/`. To make changes in the Grafana UI, duplicate the item you
wish to change, make your changes, test it and export the JSON.

Some items can be exported with the option
`Export the dashboard to use in another instance`, which should be used when
it's available.
