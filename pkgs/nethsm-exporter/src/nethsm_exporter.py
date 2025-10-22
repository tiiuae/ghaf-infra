#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""NetHSM Exporter"""

import argparse
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import cast, final, override

import requests
import urllib3
from loguru import logger
from prometheus_client import (
    GC_COLLECTOR,
    PLATFORM_COLLECTOR,
    PROCESS_COLLECTOR,
    REGISTRY,
    start_http_server,
)
from prometheus_client.core import GaugeMetricFamily
from prometheus_client.registry import Collector
from requests.auth import HTTPBasicAuth

# Suppress SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def sanitize_metric_name(name: str) -> str:
    """Turn metric name into format that prometheus excepts"""
    name = name.lower()
    name = re.sub(r"[ .]", "_", name)
    name = re.sub(r"[^a-z0-9_]", "", name)
    return f"nethsm_{name}"


@final
class HSMCollector(Collector):  # pylint: disable=too-few-public-methods
    """Custom prometheus collector"""

    def __init__(self, host: str, username: str, password: str):
        self.host = host
        self.username = username
        self.password = password

    @override
    def collect(self):
        """This gets run on GET /metrics"""
        try:
            logger.info(f"Collecting metrics from {self.host}...")
            response = requests.get(
                f"https://{self.host}/api/v1/metrics",
                auth=HTTPBasicAuth(self.username, self.password),
                verify=False,
                timeout=5,
            )

            response.raise_for_status()
            data = cast(dict[str, str], response.json())

            # Mark scrape as successful
            yield GaugeMetricFamily(
                "nethsm_up",
                "Whether scraping NetHSM was successful",
                value=1,
            )

            http_response_family = GaugeMetricFamily(
                "nethsm_http_response",
                "HTTP responses by status code",
                labels=["code"],
            )

            for key, value in data.items():
                try:
                    metric_value = float(value)
                except ValueError:
                    continue

                if (
                    key.startswith("http response ")
                    and (code := key.split(" ")[-1]).isdigit()
                ):
                    http_response_family.add_metric([code], metric_value)
                else:
                    metric_name = sanitize_metric_name(key)
                    yield GaugeMetricFamily(
                        metric_name,
                        key,
                        value=metric_value,
                    )

            if http_response_family.samples:
                yield http_response_family

        except (
            requests.exceptions.HTTPError,
            requests.exceptions.ConnectionError,
        ) as e:
            logger.error(f"Error collecting metrics: {e}")

            yield GaugeMetricFamily(
                "nethsm_up",
                "Whether scraping NetHSM was successful",
                value=0,
            )


@dataclass
class Args(argparse.Namespace):
    """Argument namespace for type checking"""

    hsm_host: str = ""
    port: int = 8000


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="NetHSM Prometheus Exporter")
    _ = parser.add_argument(
        "--hsm-host",
        required=True,
        help="NetHSM hostname",
    )
    _ = parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Port to expose Prometheus metrics on",
    )
    args = parser.parse_args(namespace=Args)

    nethsm_username: str | None = os.getenv("NETHSM_USER")
    nethsm_password: str | None = os.getenv("NETHSM_PASSWORD")

    if not nethsm_username or not nethsm_password:
        logger.error(
            "Environment variables NETHSM_USER and NETHSM_PASSWORD must be set"
        )
        sys.exit(1)

    # disable default collectors
    REGISTRY.unregister(GC_COLLECTOR)
    REGISTRY.unregister(PLATFORM_COLLECTOR)
    REGISTRY.unregister(PROCESS_COLLECTOR)

    # add our custom collector
    REGISTRY.register(HSMCollector(args.hsm_host, nethsm_username, nethsm_password))

    _ = start_http_server(args.port)
    logger.info("Prometheus exporter running on :8000/metrics")

    try:
        # keep alive
        while True:
            time.sleep(1)

    except SystemExit:
        print("\nQuitting\n")
        sys.exit()
