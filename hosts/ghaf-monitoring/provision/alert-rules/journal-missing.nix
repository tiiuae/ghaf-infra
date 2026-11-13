# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, hosts }:
{
  uid = "journal-missing";
  title = "journal logs missing";
  condition = "C";
  data = [
    {
      refId = "A";
      queryType = "instant";
      relativeTimeRange = {
        from = 1800;
        to = 0;
      };
      datasourceUid = "loki";
      model = {
        refId = "A";
        # Keep a stable host label on both 0 and 1, so recovery is explicit.
        # Updating this single rule also retires removed hosts' alert instances.
        expr =
          if hosts == [ ] then
            "vector(0)"
          else
            lib.concatMapStringsSep " or " (
              host:
              ''label_replace(sum(absent_over_time({job="systemd-journal",host=${builtins.toJSON host}}[30m])) or vector(0), "host", ${builtins.toJSON host}, "", "")''
            ) hosts;
        queryType = "instant";
        instant = true;
        editorMode = "code";
        intervalMs = 1000;
        maxDataPoints = 43200;
      };
    }
    {
      refId = "C";
      relativeTimeRange = {
        from = 0;
        to = 0;
      };
      datasourceUid = "__expr__";
      model = {
        refId = "C";
        type = "threshold";
        expression = "A";
        conditions = [
          {
            evaluator = {
              type = "gt";
              params = [ 0 ];
            };
            operator.type = "and";
            query.params = [ "C" ];
            reducer = {
              type = "last";
              params = [ ];
            };
            type = "query";
          }
        ];
      };
    }
  ];
  noDataState = "NoData";
  execErrState = "Error";
  for = "0s";
  annotations.summary = "{{ $labels.host }}: no systemd journal logs received by Loki for 30 minutes";
  isPaused = false;
}
