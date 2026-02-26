<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Nebula overlay network

> [Nebula](https://github.com/slackhq/nebula) is a scalable overlay networking tool with a focus on performance,
simplicity and security. It lets you seamlessly connect computers anywhere in the world.

Nebula is used in ghaf-infra to create a network between servers in the Tampere office and hetzner.

![diagram](./nebula-monitoring.png)

## Lighthouse

Nebula network needs to have at least one "lighthouse" host. This host should be publicly available,
and will introduce any new hosts that join the network.
Note that no traffic flows though the lighthouse, it is simply a discovery node.

Our lighthouse is `ghaf-lighthouse` on hetzner.

The lighthouse can also be used as a DNS server to resolve the host ip addresses.
We have the following DNS records to facilitate this:

```
sumu.vedenemo.dev. 0  NS  sumu.vedenemo.dev.
sumu.vedenemo.dev. 0  A   65.109.141.136
```

Query like `dig monitoring.sumu.vedenemo.dev` will return the nebula address of our monitoring server.
The address if of course only reachable from within the network.

From within the nebula network, and using the nebula address of the lighthouse, you can also query the cert of any host:

```sh
dig @10.42.42.1 10.42.42.11 txt
```

This will tell you the groups that the host (10.42.42.11) is part of, if you forgot.

## Certificate Authority

The CA key and cert are stored encrypted in `services/nebula/ca.{key,crt}`.
These can be decrypted with SOPS, given you have the rights:

```sh
sops decrypt ca.key
```

The current keys have been generated with this command:

```sh
nebula-cert ca --name "Vedenemo CA"
```

Note that the CA has lifetime of 1 year. See how to rotate the keys
[here](https://nebula.defined.net/docs/guides/rotating-certificate-authority)

## Host Certificates

Helper script is provided in `scripts/nebula-sign.sh`, which will decrypt the ca keys into a temporary directory
and run `nebula-cert sign` with the arguments you provide. After exiting, the temporary directory gets deleted.

### Example usage

create new host certificate for `testagent-dev` and assign it the ip address `10.42.42.11` on the nebula network
(Check hosts/machines.nix so you don't pick already occupied address).
This host will be part of the groups `testagent` and `office`.
The groups can be anything and are used to define firewall rules between hosts.

`sumu.vedenemo.dev` has been chosen as the subdomain of our nebula network so all hostnames should be under that.

```sh
./scripts/nebula-sign.sh -name "testagent-dev.sumu.vedenemo.dev" -ip "10.42.42.11/24" -groups "testagent,office"
```

Other groups we are using:
    - hetzner
    - scraper

The script will print the cert and key in a format that can be easily copy-pasted into `secrets.yaml`.

## Nix configuration

To add a new host into the network, you should have the certificate and key in `secrets.yaml`,
then import the `service-nebula` module.

Set secret owner as `config.nebula.user` (this is defined in the module).

```nix
sops.secrets = {
  nebula-cert.owner = config.nebula.user;
  nebula-key.owner = config.nebula.user;
};
```

Then you can enable the nebula module:

```nix
nebula = {
  enable = true;
  cert = config.sops.secrets.nebula-cert.path;
  key = config.sops.secrets.nebula-key.path;
};
```

Remember to update `.sops.yaml` and then run `sops updatekeys services/nebula/ca.crt.crypt`.
The new host should be able to decrypt `ca.crt.crypt` for nebula to run.

## Onboarding checklist

End-to-end steps for adding a host to the Nebula network. This assumes the
host already exists in the infrastructure (see
[adding a host](./adding-a-host.md) for the full setup).

1. **Pick an IP** — choose the next free `10.42.42.x` address by checking
   existing `nebula_ip` values in `hosts/machines.nix`.
2. **Choose groups** — select the appropriate groups for the host (see
   [firewall groups](#firewall-groups) below).
3. **Sign a certificate** — run `./scripts/nebula-sign.sh` with the chosen
   name, IP, and groups:
   ```sh
   ./scripts/nebula-sign.sh -name "<name>.sumu.vedenemo.dev" -ip "10.42.42.x/24" -groups "group1,group2"
   ```
4. **Add cert and key to secrets** — copy the script output into the host's
   `secrets.yaml` (the `nebula-cert` and `nebula-key` fields).
5. **Update `.sops.yaml`** — add the host's age key anchor to the
   `services/nebula/ca.crt.crypt` creation rule so the host can decrypt it.
6. **Re-encrypt** — run `sops updatekeys services/nebula/ca.crt.crypt`.
7. **Configure NixOS** — import the `service-nebula` module in the host's
   `configuration.nix` and enable it (see [Nix configuration](#nix-configuration)
   above).
8. **Add `nebula_ip`** — set the `nebula_ip` field in `hosts/machines.nix`.
9. **Deploy** — deploy the host with `deploy .#<name>`.

## Firewall groups

Groups are assigned when signing a host certificate and are used in the
Nebula firewall rules defined in `services/nebula/default.nix`.

| Group | Purpose |
|---|---|
| `hetzner` | Hetzner cloud nodes |
| `office` | Tampere office nodes |
| `testagent` | Test agent machines |
| `scraper` | Metrics scraping (ghaf-monitoring) |
| `uae-lab` | UAE lab nodes |

The `scraper` group is used in an inbound firewall rule that allows
ghaf-monitoring to scrape Prometheus node-exporter metrics (port 9100/tcp)
from any host in that group. Other groups are currently informational and
can be used to add targeted firewall rules as needed.
