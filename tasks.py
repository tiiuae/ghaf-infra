#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2023 Nix community projects
# SPDX-License-Identifier: MIT

# This file originates from:
# https://github.com/nix-community/infra/blob/c4c8c32b51/tasks.py

################################################################################

# Basic usage:
#
# List tasks:
# $ inv --list
#
# Get help (using 'deploy' task as an example):
# $ inv --help deploy
#
# Run a task (using build-local as an example):
# $ inv build-local
#
# For more pyinvoke usage examples, see:
# https://docs.pyinvoke.org/en/stable/getting-started.html


"""Misc dev and deployment helper tasks"""

import json
import logging
import os
import socket
import subprocess
import sys
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Optional

from colorlog import ColoredFormatter, default_log_colors
from deploykit import DeployHost, HostKeyCheck
from invoke.tasks import task
from tabulate import tabulate

################################################################################

ROOT = Path(__file__).parent.resolve()
os.chdir(ROOT)
LOG = logging.getLogger(os.path.abspath(__file__))

################################################################################


@dataclass(eq=False)
class TargetHost:
    """Represents target host"""

    hostname: str
    nixosconfig: str
    secretspath: Optional[str] = None


# Below dictionary defines the set of ghaf-infra configuration aliases:
#  - Name (e.g. 'binarycache-ficolo') defines the alias name for each target.
#  - TargetHost.hostname: host name or IP address of the target.
#  - TargetHost.nixosconfig: name of the target nixosConfiguration.
TARGETS = OrderedDict(
    {
        "binarycache-ficolo": TargetHost(
            hostname="172.18.20.109",
            nixosconfig="binarycache",
            secretspath="hosts/binarycache/secrets.yaml",
        ),
        "monitoring-ficolo": TargetHost(
            hostname="172.18.20.108",
            nixosconfig="monitoring",
            secretspath="hosts/monitoring/secrets.yaml",
        ),
        "build3-ficolo": TargetHost(
            hostname="172.18.20.104",
            nixosconfig="build3",
            secretspath="hosts/builder/build3/secrets.yaml",
        ),
        "build4-ficolo": TargetHost(
            hostname="172.18.20.105",
            nixosconfig="build4",
        ),
        "himalia": TargetHost(
            hostname="172.18.20.106",
            nixosconfig="himalia",
        ),
        "testagent-dev": TargetHost(
            hostname="172.18.16.33",
            nixosconfig="testagent-dev",
            secretspath="hosts/testagent/dev/secrets.yaml",
        ),
        "testagent-prod": TargetHost(
            hostname="172.18.16.60",
            nixosconfig="testagent-prod",
            secretspath="hosts/testagent/prod/secrets.yaml",
        ),
        "testagent-release": TargetHost(
            hostname="172.18.16.32",
            nixosconfig="testagent-release",
            secretspath="hosts/testagent/release/secrets.yaml",
        ),
        "hetzarm": TargetHost(
            hostname="65.21.20.242",
            nixosconfig="hetzarm",
            secretspath="hosts/hetzarm/secrets.yaml",
        ),
        "ghaf-log": TargetHost(
            hostname="95.217.177.197",
            nixosconfig="ghaf-log",
            secretspath="hosts/ghaf-log/secrets.yaml",
        ),
        "ghaf-coverity": TargetHost(
            hostname="135.181.103.32",
            nixosconfig="ghaf-coverity",
            secretspath="hosts/ghaf-coverity/secrets.yaml",
        ),
        "ghaf-proxy": TargetHost(
            hostname="95.216.200.85",
            nixosconfig="ghaf-proxy",
            secretspath="hosts/ghaf-proxy/secrets.yaml",
        ),
        "ghaf-webserver": TargetHost(
            hostname="37.27.204.82",
            nixosconfig="ghaf-webserver",
            secretspath="hosts/ghaf-webserver/secrets.yaml",
        ),
        "testagent-uae-dev": TargetHost(
            hostname="172.19.16.12",
            nixosconfig="testagent-uae-dev",
            secretspath="hosts/testagent/uae-dev/secrets.yaml",
        ),
    }
)


def _get_target(alias: str) -> TargetHost:
    if alias not in TARGETS:
        LOG.fatal("Unknown alias '%s'", alias)
        sys.exit(1)
    return TARGETS[alias]


################################################################################


def set_log_verbosity(verbosity: int = 1) -> None:
    """Set logging verbosity (0=NOTSET, 1=INFO, or 2=DEBUG)"""
    log_levels = [logging.NOTSET, logging.INFO, logging.DEBUG]
    verbosity = min(len(log_levels) - 1, max(verbosity, 0))
    _init_logging(verbosity)


def _init_logging(verbosity: int = 1) -> None:
    """Initialize logging"""
    if verbosity == 0:
        level = logging.NOTSET
    elif verbosity == 1:
        level = logging.INFO
    else:
        level = logging.DEBUG
    if level <= logging.DEBUG:
        logformat = (
            "%(log_color)s%(levelname)-8s%(reset)s "
            "%(filename)s:%(funcName)s():%(lineno)d "
            "%(message)s"
        )
    else:
        logformat = "%(log_color)s%(levelname)-8s%(reset)s %(message)s"
    default_log_colors["INFO"] = "fg_bold_white"
    default_log_colors["DEBUG"] = "fg_bold_white"
    default_log_colors["SPAM"] = "fg_bold_white"
    formatter = ColoredFormatter(logformat, log_colors=default_log_colors)
    if LOG.hasHandlers() and len(LOG.handlers) > 0:
        stream = LOG.handlers[0]
    else:
        stream = logging.StreamHandler()
    stream.setFormatter(formatter)
    if not LOG.hasHandlers():
        LOG.addHandler(stream)
    LOG.setLevel(level)


# Set logging verbosity (1=INFO, 2=DEBUG)
set_log_verbosity(1)


def exec_cmd(
    cmd, raise_on_error=True, capture_output=True
) -> subprocess.CompletedProcess | None:
    """Run shell command cmd"""
    LOG.info("Running: %s", cmd)
    try:
        if capture_output:
            return subprocess.run(
                cmd.split(), capture_output=True, text=True, check=True
            )
        return subprocess.run(
            cmd.split(), text=True, check=True, stdout=subprocess.PIPE
        )
    except subprocess.CalledProcessError as error:
        warn = [f"'{cmd}':"]
        if error.stdout:
            warn.append(f"{error.stdout}")
        if error.stderr:
            warn.append(f"{error.stderr}")
        LOG.warning("\n".join(warn))
        if raise_on_error:
            raise error
        return None


################################################################################


@task
def alias_list(_c: Any) -> None:
    """
    List available targets (i.e. configurations and alias names)

    Example usage:
    inv list-name
    """
    table_rows = []
    table_rows.append(["alias", "nixosconfig", "hostname"])
    for alias, host in TARGETS.items():
        row = [alias, host.nixosconfig, host.hostname]
        table_rows.append(row)
    table = tabulate(table_rows, headers="firstrow", tablefmt="fancy_outline")
    print(f"\nCurrent ghaf-infra targets:\n\n{table}")


@task
def update_sops_files(c: Any) -> None:
    """
    Update all sops yaml and json files according to .sops.yaml rules.

    Example usage:
    inv update-sops-files
    """
    c.run(
        r"""
find . \
        -type f \
        \( -iname '*.enc.json' -o -iname 'secrets.yaml' \) \
        -exec sops updatekeys --yes {} \;
"""
    )


@task
def print_keys(_c: Any, alias: str) -> None:
    """
    Decrypt host private key, print ssh and age public keys for `alias` config.

    Example usage:
    inv print-keys --target binarycache-ficolo
    """
    target = _get_target(alias)
    with TemporaryDirectory() as tmpdir:
        decrypt_host_key(target, tmpdir)
        key = f"{tmpdir}/etc/ssh/ssh_host_ed25519_key"
        pubkey = subprocess.run(
            ["ssh-keygen", "-y", "-f", f"{key}"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        print("###### Public keys ######")
        print(pubkey.stdout)
        print("###### Age keys ######")
        subprocess.run(
            ["ssh-to-age"],
            input=pubkey.stdout,
            check=True,
            text=True,
        )


def get_deploy_host(alias: str = "") -> DeployHost:
    """
    Return DeployHost object, given `alias`
    """
    hostname = _get_target(alias).hostname
    deploy_host = DeployHost(
        host=hostname,
        host_key_check=HostKeyCheck.NONE,
        # verbose_ssh=True,
    )
    return deploy_host


@task
def deploy(_c: Any, alias: str) -> None:
    """
    Deploy the configuration for `alias`.

    Example usage:
    inv deploy --alias binarycache-ficolo
    """
    h = get_deploy_host(alias)
    res = h.run_local(
        ["nix", "flake", "archive", "--to", f"ssh://{h.host}", "--json"],
        stdout=subprocess.PIPE,
    )
    data = json.loads(res.stdout)
    path = data["path"]
    LOG.debug("data['path']: %s", path)
    flags = "--option accept-flake-config true"
    nixosconfig = _get_target(alias).nixosconfig
    command = "sudo nixos-rebuild"
    h.run(f"{command} switch {flags} --flake {path}#{nixosconfig}")


def decrypt_host_key(target: TargetHost, tmpdir: str) -> None:
    """
    Run sops to extract `nixosconfig` secret 'ssh_host_ed25519_key'
    """

    def opener(path: str, flags: int) -> int:
        return os.open(path, flags, 0o400)

    t = Path(tmpdir)
    t.mkdir(parents=True, exist_ok=True)
    t.chmod(0o755)
    host_key = t / "etc/ssh/ssh_host_ed25519_key"
    host_key.parent.mkdir(parents=True, exist_ok=True)
    with open(host_key, "w", opener=opener, encoding="utf-8") as fh:
        try:
            subprocess.run(
                [
                    "sops",
                    "--extract",
                    '["ssh_host_ed25519_key"]',
                    "--decrypt",
                    f"{ROOT}/{target.secretspath}",
                ],
                check=True,
                stdout=fh,
            )
        except subprocess.CalledProcessError:
            LOG.warning(
                "Failed reading secret 'ssh_host_ed25519_key' for '%s'",
                target.nixosconfig,
            )
            ask = input("Still continue? [y/N] ")
            if ask != "y":
                sys.exit(1)
        else:
            pub_key = t / "etc/ssh/ssh_host_ed25519_key.pub"
            with open(pub_key, "w", encoding="utf-8") as fh:
                subprocess.run(
                    ["ssh-keygen", "-y", "-f", f"{host_key}"],
                    stdout=fh,
                    text=True,
                    check=True,
                )
            pub_key.chmod(0o644)


@task
def install(c: Any, alias) -> None:
    """
    Install `alias` configuration using nixos-anywhere, deploying host private key.
    Note: this will automatically partition and re-format the target hard drive,
    meaning all data on the target will be completely overwritten with no option
    to rollback.

    Example usage:
    inv install --alias ghafscan-dev
    """
    h = get_deploy_host(alias)

    ask = input(f"Install configuration '{alias}'? [y/N] ")
    if ask != "y":
        return

    # Check ssh and remote user
    try:
        remote_user = h.run(cmd="whoami", stdout=subprocess.PIPE).stdout.strip()
        cmd = exec_cmd("whoami")
        # error will be raised before the value is None
        # this is here to make the type checker happy
        assert cmd is not None
        local_user = cmd.stdout.strip()
        if remote_user and local_user and remote_user != local_user:
            LOG.warning(
                "Remote user '%s' is not your current local user. "
                "You will likely not be able to login to the remote host '%s' "
                "after nixos-anywhere installation. Consider adding your local "
                "user to the remote host and make sure user '%s' "
                "also has access to remote host after nixos-anywhere installation "
                "by adding your local user as a user to nixos configuration '%s'. "
                "Hint: you might want to try the helper script at "
                "'scripts/add-remote-user.sh' to add your current local "
                "user to the remote host.",
                remote_user,
                _get_target(alias).hostname,
                local_user,
                _get_target(alias).nixosconfig,
            )
            ask = input("Still continue? [y/N] ")
            if ask != "y":
                sys.exit(1)
    except subprocess.CalledProcessError:
        LOG.fatal("No ssh access to the remote host")
        sys.exit(1)
    # Check sudo nopasswd
    try:
        h.run("sudo -n true", become_root=True)
    except subprocess.CalledProcessError:
        LOG.warning(
            "sudo on '%s' needs password: installation will likely fail", h.host
        )
        ask = input("Still continue? [y/N] ")
        if ask != "y":
            sys.exit(1)
    # Check dynamic ip
    try:
        h.run("ip a | grep dynamic")
    except subprocess.CalledProcessError:
        pass
    else:
        LOG.warning("Above address(es) on '%s' use dynamic addressing.", h.host)
        LOG.warning(
            "This might cause issues if you assume the target host is reachable "
            "from any such address also after kexec switch. "
            "If you do, consider making the address temporarily static "
            "before continuing."
        )
        ask = input("Still continue? [y/N] ")
        if ask != "y":
            sys.exit(1)

    target = _get_target(alias)
    with TemporaryDirectory() as tmpdir:
        decrypt_host_key(target, tmpdir)
        gitrev = "97b45ac774699b1cfd267e98a8bdecb74bace593"
        command = f"nix run github:numtide/nixos-anywhere?rev={gitrev} --"
        command += f" {h.host} --extra-files {tmpdir} --flake .#{target.nixosconfig}"
        command += " --option accept-flake-config true"
        LOG.warning(command)
        c.run(command)

    # Reboot
    print(f"Wait for {h.host} to start", end="")
    wait_for_port(h.host, 22)
    reboot(c, alias)


@task
def build_local(_c: Any, alias: str = "") -> None:
    """
    Build NixOS configuration `alias` locally.
    If `alias` is not specificied, builds all TARGETS.

    Example usage:
    inv build-local --alias binarycache-ficolo
    """
    if alias:
        target_configs = [_get_target(alias).nixosconfig]
    else:
        target_configs = [target.nixosconfig for _, target in TARGETS.items()]
    for nixosconfig in target_configs:
        cmd = (
            "nixos-rebuild build --option accept-flake-config true "
            f" -v --flake .#{nixosconfig}"
        )
        exec_cmd(cmd, capture_output=False)


def wait_for_port(host: str, port: int, shutdown: bool = False) -> None:
    """Wait for `host`:`port`"""

    while True:
        time.sleep(1)
        sys.stdout.write(".")
        sys.stdout.flush()
        try:
            with socket.create_connection((host, port), timeout=1):
                if not shutdown:
                    break
        except OSError:
            if shutdown:
                break
    print("")


@task
def reboot(_c: Any, alias: str) -> None:
    """
    Reboot host identified as `alias`.

    Example usage:
    inv reboot --alias binarycache-ficolo
    """
    h = get_deploy_host(alias)
    h.run("sudo reboot &")

    print(f"Wait for {h.host} to shutdown", end="")
    sys.stdout.flush()
    port = h.port or 22
    wait_for_port(h.host, port, shutdown=True)

    print(f"Wait for {h.host} to start", end="")
    sys.stdout.flush()
    wait_for_port(h.host, port)


@task
def pre_push(c: Any) -> None:
    """
    Run 'pre-push' checks.
    Also, build all nixosConfiguration targets in this flake.

    Example usage:
    inv pre-push
    """
    cmd = "nix flake check -v"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    build_local(c)
    LOG.info("All pre-push checks passed")
