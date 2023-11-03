#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2023 Technology Innovation Institute (TII)
# SPDX-FileCopyrightText: 2023 Nix community projects
#
# SPDX-License-Identifier: MIT

# This file originates from:
# https://github.com/nix-community/infra/blob/c4c8c32b51/tasks.py

################################################################################

# pylint: disable=invalid-name

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


""" Misc dev and deployment helper tasks """

import json
import os
import subprocess
import sys
import logging
import socket
import time
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Union

from colorlog import ColoredFormatter, default_log_colors
from deploykit import DeployHost, DeployGroup, HostKeyCheck
from invoke import task

################################################################################

ROOT = Path(__file__).parent.resolve()
os.chdir(ROOT)
LOG = logging.getLogger(os.path.abspath(__file__))

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


def exec_cmd(cmd, raise_on_error=True):
    """Run shell command cmd"""
    LOG.debug("Running: %s", cmd)
    try:
        return subprocess.run(cmd.split(), capture_output=True, text=True, check=True)
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
def print_keys(_c: Any, target: str) -> None:
    """
    Decrypt host private key, print ssh and age public keys for `target`.

    Example usage:
    inv print-keys --target ghafhydra
    """
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


def get_deploy_host(target: str = "", hostname: str = "") -> DeployHost:
    """
    Return DeployHost object, given `hostname` and `target`
    """
    deploy_host = DeployHost(
        host=hostname,
        meta={"target": target},
        host_key_check=HostKeyCheck.NONE,
        # verbose_ssh=True,
    )
    return deploy_host


@task
def deploy(_c: Any, target: str, hostname: str) -> None:
    """
    Deploy NixOS configuration `target` to host `hostname`.

    Example usage:
    inv deploy --target ghafhydra --hostname 192.168.1.107
    """
    h = get_deploy_host(target, hostname)
    command = "sudo nixos-rebuild"
    res = h.run_local(
        ["nix", "flake", "archive", "--to", f"ssh://{h.host}", "--json"],
        stdout=subprocess.PIPE,
    )
    data = json.loads(res.stdout)
    path = data["path"]
    LOG.debug("data['path']: %s", path)
    flags = "--option accept-flake-config true"
    h.run(f"{command} switch {flags} --flake {path}#{h.meta['target']}")


def decrypt_host_key(target: str, tmpdir: str) -> None:
    """
    Run sops to extract `target` secret 'ssh_host_ed25519_key'
    """

    def opener(path: str, flags: int) -> Union[str, int]:
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
                    f"{ROOT}/hosts/{target}/secrets.yaml",
                ],
                check=True,
                stdout=fh,
            )
        except subprocess.CalledProcessError:
            LOG.warning("Failed reading secret 'ssh_host_ed25519_key' for '%s'", target)
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
def install(c: Any, target: str, hostname: str) -> None:
    """
    Install `target` on `hostname` using nixos-anywhere, deploying host private key.
    Note: this will automatically partition and re-format `hostname` hard drive,
    meaning all data on the target will be completely overwritten with no option
    to rollback.

    Example usage:
    inv install --target ghafscan --hostname 192.168.1.109
    """
    ask = input(f"Install configuration '{target}' on host '{hostname}'? [y/N] ")
    if ask != "y":
        return

    h = get_deploy_host(target, hostname)
    # Check sudo nopasswd
    try:
        h.run("sudo -nv", become_root=True)
    except subprocess.CalledProcessError:
        LOG.warning(
            "sudo on '%s' needs password: installation will likely fail", hostname
        )
        ask = input("Still continue? [y/N] ")
        if ask != "y":
            sys.exit(1)
    # Check static ip
    try:
        h.run("ip a | grep dynamic")
    except subprocess.CalledProcessError:
        pass
    else:
        LOG.warning("Above address(es) on '%s' use dynamic addressing.", hostname)
        LOG.warning(
            "This might cause issues if you assume the target host is reachable "
            "from any such address also after kexec switch. "
            "If you do, consider making the address temporarily static "
            "before continuing."
        )
        ask = input("Still continue? [y/N] ")
        if ask != "y":
            sys.exit(1)

    with TemporaryDirectory() as tmpdir:
        decrypt_host_key(target, tmpdir)
        command = "nix run github:numtide/nixos-anywhere --"
        command += f" {hostname} --extra-files {tmpdir} --flake .#{target}"
        command += " --option accept-flake-config true"
        c.run(command)
    # Reboot
    print(f"Wait for {hostname} to start", end="")
    wait_for_port(hostname, 22)
    reboot(c, hostname)


@task
def build_local(_c: Any, target: str = "") -> None:
    """
    Build NixOS configuration `target` locally.
    If `target` is not specificied, builds all nixosConfigurations in the flake.

    Example usage:
    inv build-local --target ghafhydra
    """
    if target:
        # For local builds, we pretend hostname is the target
        g = DeployGroup([get_deploy_host(hostname=target)])
    else:
        res = subprocess.run(
            ["nix", "flake", "show", "--json"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        data = json.loads(res.stdout)
        targets = data["nixosConfigurations"]
        g = DeployGroup([get_deploy_host(hostname=t) for t in targets])

    def _build_local(h: DeployHost) -> None:
        h.run_local(
            [
                "nixos-rebuild",
                "build",
                "--option",
                "accept-flake-config",
                "true",
                "--flake",
                f".#{h.host}",
            ]
        )

    g.run_function(_build_local)


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
def reboot(_c: Any, hostname: str) -> None:
    """
    Reboot host `hostname`.

    Example usage:
    inv reboot --hostname 192.168.1.112
    """
    h = get_deploy_host(hostname=hostname)
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
    Run 'pre-push' checks: black, pylint, pycodestyle, reuse lint, nix fmt.
    Also, build all nixosConfiguration targets in this flake.

    Example usage:
    inv pre-push
    """
    cmd = "find . -type f -name *.py ! -path *result* ! -path *eggs*"
    ret = exec_cmd(cmd)
    pyfiles = ret.stdout.replace("\n", " ")
    LOG.info("Running black")
    cmd = f"black -q {pyfiles}"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Running pylint")
    cmd = f"pylint --disable duplicate-code -rn {pyfiles}"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Running pycodestyle")
    cmd = f"pycodestyle --max-line-length=90 {pyfiles}"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Running reuse lint")
    cmd = "reuse lint"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Running terraform fmt")
    cmd = "terraform fmt -check -recursive"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        LOG.warning("Run `terraform fmt -recursive` locally to fix formatting")
        sys.exit(1)
    LOG.info("Running nix fmt")
    cmd = "nix fmt"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Running nix flake check")
    cmd = "nix flake check -v --log-format raw"
    ret = exec_cmd(cmd, raise_on_error=False)
    if not ret:
        sys.exit(1)
    LOG.info("Building all nixosConfigurations")
    build_local(c)
    LOG.info("All pre-push checks passed")
