<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Monitoring

Grafana instance is publicly accessible at <https://monitoring.vedenemo.dev>.
Log in with GitHub. Access requires membership in the `tiiuae` organization
and its `devenv-fi` team.

The hosts in ghaf-infra are monitored with Grafana running on `ghaf-monitoring`.

Hosts opt in to resource metrics with `services.monitoring.metrics.enable`,
which starts `node-exporter`. Enabling `services.monitoring.logs.enable`
starts Grafana Alloy to send systemd journal logs to Loki. Both default to off.

The monitoring server has an additional Hetzner volume attached which stores the
state (metrics and logs) of Grafana, Prometheus & Loki.

## Hosts

The eight Prometheus jobs below are configured in
[`hosts/ghaf-monitoring/configuration.nix`](../hosts/ghaf-monitoring/configuration.nix).
Enabling an exporter does not add a host to a scrape job; most target lists
must be updated explicitly.

### Hetzner Cloud

The `hetzner-cloud` job scrapes hosts listed in `hetznerCloudHosts` at their
`internal_ip` on port 9100 over the Hetzner private network, without
authentication.

The `zot` job scrapes registry metrics from `ghaf-registry` at its
`internal_ip` on port 443, using HTTPS and basic authentication.

### Hetzner Robot

Hetzner robot side machines cannot join the internal network the same way cloud
machines can. For this reason, they are monitored through an ssh proxy
(`sshified`). The scrape job `hetzner-robot` sends its traffic through this
proxy to hosts listed in `hetznerRobotHosts`, on port 9100.

### On-prem

The `office` job scrapes the five Tampere test agents and `nethsm-gateway`
at their `nebula_ip` addresses on port 9100. These hosts must join Nebula
and allow access from the monitoring server.

#### relay-board

The `relay-board` job scrapes `testagent-dev`, `testagent2-prod`, and
`testagent-release` on port 8000 using their `sumu.vedenemo.dev` names.
These agents run `relay_board_exporter.py` to expose relay board status.

#### NetHSM

The `nethsm` job scrapes `nethsm-gateway` and `uae-nethsm-gateway` on port
8000 using their `sumu.vedenemo.dev` names. Each runs `nethsm-exporter`,
which collects metrics from the NetHSM REST API. `nethsm-gateway-dev` also
enables the exporters, but is absent from the `office` and `nethsm` jobs.

The gateways also send NetHSM logs in addition to systemd logs to Loki.

### UAE

The `uae` job scrapes `uae-azureci-prod` and `uae-nethsm-gateway` at their
`nebula_ip` addresses on port 9100.

### Nebula metrics

The `nebula` job includes every host with a `nebula_ip` in `hosts/machines.nix`.
It scrapes Nebula metrics on port 9101, using `internal_ip` for hosts in
`hetznerCloudHosts` and `nebula_ip` for the rest.

## ghaf-log (separate instance)

A second, independent Grafana + Loki instance runs on `ghaf-log`
(<https://ghaflogs.vedenemo.dev>). It handles Ghaf device logs separately from the
infrastructure monitoring on `ghaf-monitoring`.

| URL | Purpose |
|---|---|
| <https://ghaflogs.vedenemo.dev> | Grafana UI with GitHub login (`tiiuae` org, `devenv-fi` and `phone` teams) |
| <https://loki.ghaflogs.vedenemo.dev> | Loki push/query API with basic authentication |

External log producers (e.g. Ghaf devices running Alloy or promtail) can push
logs to the Loki endpoint. Credentials are stored in
`hosts/ghaf-log/secrets.yaml` (`loki_basic_auth`).

Like `ghaf-monitoring`, state is stored on a Hetzner volume under `/data/`.

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
