#!/usr/bin/env python3
# pylint: disable=import-error,import-outside-toplevel
# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""
KMTronic Relay Board Prometheus Exporter + Control API + Embedded UI
"""

import json
import subprocess

from fastapi import FastAPI, HTTPException, Form
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

CONFIG_PATH = "/etc/jenkins/test_config.json"
PORT = 8000

app = FastAPI(title="KMTronic Relay Board Exporter")

# ---------------------------------------------------------------------
# Relay logic
# ---------------------------------------------------------------------


def load_relay_config(config_path: str) -> tuple[str, dict]:
    """Load serial port and relay mappings from configuration file."""
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        addresses = data.get("addresses", {})
        serial_port = addresses.get("relay_serial_port", "")

        relay_map = {}
        for key, value in addresses.items():
            if isinstance(value, dict) and "relay_number" in value:
                relay_map[str(value["relay_number"])] = f"relay-{key}"

        return serial_port, relay_map

    except (FileNotFoundError, json.JSONDecodeError):
        return "", {}


def read_relay_raw_state(serial_port: str) -> dict:
    """Read relay states using kmtronic-status CLI."""
    try:
        result = subprocess.run(
            ["kmtronic-status", serial_port],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError:
        return {}

    states = {}
    for idx, line in enumerate(result.stdout.strip().splitlines(), start=1):
        parts = line.split()
        states[str(idx)] = parts[2] if len(parts) >= 3 else "OFF"

    return states


def set_relay_state(serial_port: str, relay_num: str, state: str) -> None:
    """Set relay state using kmtronic-control CLI."""
    state = state.upper()
    if state not in ("ON", "OFF"):
        raise ValueError("Invalid relay state")

    subprocess.run(
        ["kmtronic-control", serial_port, state, relay_num],
        check=True,
        capture_output=True,
        text=True,
    )


def _resolve_relay(relay_name: str) -> str:
    """Resolve relay name to raw relay number."""
    if relay_name.startswith("relay-"):
        candidate = relay_name.split("relay-", 1)[1]
        if candidate.isdigit():
            return candidate

        for raw, name in RELAY_MAP.items():
            if name == relay_name:
                return raw

    raise HTTPException(status_code=404, detail="Unknown relay")


def _do_set_relay(relay: str, state: str) -> None:
    """Shared relay switch logic for API and UI."""
    raw = _resolve_relay(relay)
    set_relay_state(SERIAL_PORT, raw, state)


# ---------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------

SERIAL_PORT, RELAY_MAP = load_relay_config(CONFIG_PATH)

if not SERIAL_PORT or SERIAL_PORT in ("NONE", "null"):
    raise SystemExit(
        f"[relay-board-exporter] relay_serial_port not configured in {CONFIG_PATH}"
    )

# ---------------------------------------------------------------------
# Prometheus metrics
# ---------------------------------------------------------------------


@app.get("/metrics", response_class=PlainTextResponse)
def metrics():
    """Expose relay states as Prometheus metrics."""
    states = read_relay_raw_state(SERIAL_PORT)

    lines = [
        "# HELP relay_status Relay ON/OFF status",
        "# TYPE relay_status gauge",
    ]

    max_relays = max(
        [int(k) for k in states] + [int(k) for k in RELAY_MAP],
        default=0,
    )

    for relay_num in range(1, max_relays + 1):
        raw = str(relay_num)
        state = states.get(raw, "OFF")
        value = 1 if state == "ON" else 0
        name = RELAY_MAP.get(raw, f"relay-{relay_num}")
        lines.append(f'relay_status{{relay="{name}"}} {value}')

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------
# API
# ---------------------------------------------------------------------


@app.get("/api/get_all")
def api_get_all():
    """Return all relay states."""
    states = read_relay_raw_state(SERIAL_PORT)
    return {RELAY_MAP.get(raw, f"relay-{raw}"): state for raw, state in states.items()}


@app.get("/api/get_state")
def api_get_state(relay: str):
    """Return state of a single relay."""
    raw = _resolve_relay(relay)
    states = read_relay_raw_state(SERIAL_PORT)
    return {"relay": relay, "state": states.get(raw, "OFF")}


@app.post("/api/set_state")
def api_set_state(relay: str = Form(...), state: str = Form(...)):
    """Set relay state via API."""
    _do_set_relay(relay, state)
    return {"status": "Relay set OK"}


# ---------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------


def render_ui(relays):
    """Render HTML UI."""
    rows = ""
    for r in relays:
        toggle_state = "OFF" if r["state"] == "ON" else "ON"
        rows += f"""
        <tr>
          <td>{r["name"]}</td>
          <td class="{r["state"].lower()}">{r["state"]}</td>
          <td>
            <form method="post" action="/relay-ui/set_state">
              <input type="hidden" name="relay" value="{r["name"]}">
              <input type="hidden" name="state" value="{toggle_state}">
              <button type="submit">Toggle</button>
            </form>
          </td>
        </tr>
        """

    return f"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Relay Control</title>
      <style>
        body {{ font-family: sans-serif; }}
        .on {{ color: green; font-weight: bold; }}
        .off {{ color: gray; }}
      </style>
    </head>
    <body>
      <h1>Relay Board</h1>
      <table>{rows}</table>
    </body>
    </html>
    """


@app.get("/relay-ui", response_class=HTMLResponse)
def relay_ui():
    """Render relay control UI."""
    states = read_relay_raw_state(SERIAL_PORT)
    relays = [
        {"name": RELAY_MAP.get(raw, f"relay-{raw}"), "state": state}
        for raw, state in states.items()
    ]
    return HTMLResponse(content=render_ui(relays))


@app.post("/relay-ui/set_state")
def relay_ui_set_state(relay: str = Form(...), state: str = Form(...)):
    """Set relay state via UI and redirect back."""
    _do_set_relay(relay, state)
    return RedirectResponse(url="/relay-ui", status_code=303)


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------


def main():
    """Start FastAPI server."""
    import uvicorn

    print(f"[relay-board-exporter] serving on port {PORT}")
    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
