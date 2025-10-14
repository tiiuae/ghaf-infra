# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_:
let
  loki_data_dir = "/var/lib/loki";
in
{
  systemd.tmpfiles.rules = [ "d /var/lib/loki 0777 loki loki - -" ];

  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;
      server = {
        http_listen_port = 3100;
        http_listen_address = "127.0.0.1";
        log_level = "warn";
      };

      common = {
        path_prefix = loki_data_dir;
        storage.filesystem = {
          chunks_directory = "${loki_data_dir}/chunks";
          rules_directory = "${loki_data_dir}/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
        ring.instance_addr = "127.0.0.1";
      };

      schema_config.configs = [
        {
          from = "2020-11-08";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index.prefix = "index_";
          index.period = "24h";
        }
      ];

      ruler = {
        alertmanager_url = "http://127.0.0.1:9093";
      };

      query_range.cache_results = true;
    };
  };
}
