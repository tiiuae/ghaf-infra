#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""
KMTronic Relay Board Prometheus Exporter

Reads relay states from KMTronic USB relay board using `kmtronic-status`
and exposes them in Prometheus metrics format via HTTP on port 8000.
"""

import json
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

# ---------------------------------------------------------------------
# Static configuration
# ---------------------------------------------------------------------
CONFIG_PATH = "/etc/jenkins/test_config.json"
PORT = 8000
# ---------------------------------------------------------------------


def load_relay_config(config_path: str) -> tuple[str, dict]:
    """Load serial port and relay mappings from configuration file."""
    try:
        with open(config_path, "r", encoding="utf-8") as config_file:
            data = json.load(config_file)

        serial_port = data.get("addresses", {}).get("relay_serial_port", "")
        entries = data.get("addresses", {})

        relay_map = {
            str(value["relay_number"]): f"relay-{key}"
            for key, value in entries.items()
            if isinstance(value, dict) and "relay_number" in value
        }

        return serial_port, relay_map

    except (FileNotFoundError, json.JSONDecodeError):
        return "", {}


def get_relay_status(serial_port: str, relay_map: dict) -> str:
    """Run kmtronic-status and convert its output into Prometheus metrics."""
    try:
        result = subprocess.run(
            ["kmtronic-status", serial_port],
            capture_output=True,
            text=True,
            check=True,
        )
        lines = result.stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return "# Error: Failed to read relay state\n"

    metrics = [
        "# HELP relay_status Relay ON/OFF status",
        "# TYPE relay_status gauge",
    ]

    for index, line in enumerate(lines, start=1):
        parts = line.split()
        state = parts[2] if len(parts) >= 3 else "OFF"
        value = 1 if state == "ON" else 0
        relay_name = relay_map.get(str(index), f"relay-{index}")
        metrics.append(f'relay_status{{relay="{relay_name}"}} {value}')

    return "\n".join(metrics) + "\n"


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler serving the /metrics endpoint for Prometheus."""

    def do_GET(self):  # noqa: N802 pylint: disable=invalid-name
        """Handle GET requests to /metrics."""
        if self.path == "/metrics":
            content = get_relay_status(
                self.server.serial_port,
                self.server.relay_map,
            )
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(content.encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, _fmt, *args):  # pylint: disable=arguments-differ
        """Suppress standard HTTP server logging."""
        return


def main():
    """Main entry point for the relay board exporter."""
    serial_port, relay_map = load_relay_config(CONFIG_PATH)

    if not serial_port or serial_port in ("NONE", "null"):
        print("[relay-board-exporter] relay_serial_port not configured — exiting.")
        return

    server = HTTPServer(("0.0.0.0", PORT), MetricsHandler)
    server.serial_port = serial_port
    server.relay_map = relay_map

    print(f"[relay-board-exporter] serving on port {PORT} (serial port: {serial_port})")

    try:
        while True:
            server.handle_request()
    except KeyboardInterrupt:
        print("\n[relay-board-exporter] stopped.")


if __name__ == "__main__":
    main()
