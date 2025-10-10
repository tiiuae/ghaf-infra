#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-FileCopyrightText: 2023 Nix community projects
# SPDX-License-Identifier: MIT

# pylint: disable=global-statement, too-many-locals

# This file originates from:
# https://github.com/nix-community/infra/blob/c4c8c32b51/tasks.py

################################################################################

# Basic usage:
#
# List tasks:
# $ inv --list
#
# Get help (using 'install' task as an example):
# $ inv --help install
#
# Run a task (using alias-list as an example):
# $ inv alias-list
#
# For more pyinvoke usage examples, see:
# https://docs.pyinvoke.org/en/stable/getting-started.html


"""Misc dev and deployment helper tasks"""

import json
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

from deploykit import DeployHost, HostKeyCheck
from invoke.tasks import task
from loguru import logger
from tabulate import tabulate


################################################################################

ROOT, TARGETS = (None, None)

################################################################################


@dataclass(eq=False)
class TargetHost:
    """Represents target host"""

    hostname: str
    nixosconfig: str
    secretspath: Optional[str] = None


class Targets:
    """Represents all installation targets"""

    populated = False
    target_dict = OrderedDict()

    def all(self) -> OrderedDict:
        """Get all hosts"""
        if not self.populated:
            self.populate()
        return self.target_dict

    def populate(self):
        """Populate the target dictionary from nix evaluation"""
        logger.debug("Reading targets")
        self.target_dict = OrderedDict(
            {
                name: TargetHost(
                    hostname=node["hostname"],
                    nixosconfig=node["config"],
                    secretspath=node["secrets"],
                )
                for name, node in json.loads(
                    subprocess.check_output(
                        ["nix", "eval", "--json", f"{ROOT}#installationTargets"]
                    )
                ).items()
            }
        )
        self.populated = True

    def get(self, alias: str) -> TargetHost:
        """Get one host"""
        logger.debug(f"Reading target '{alias}'")
        if self.populated:
            if alias not in self.target_dict:
                logger.error(f"Unknown alias '{alias}'")
                sys.exit(1)

            return self.target_dict[alias]

        node = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--json", f"{ROOT}#installationTargets.{alias}"]
            )
        )
        return TargetHost(
            hostname=node["hostname"],
            nixosconfig=node["config"],
            secretspath=node["secrets"],
        )


@task
def alias_list(_c: Any) -> None:
    """
    List available targets (i.e. configurations and alias names)

    Example usage:
    inv alias-list
    """
    table_rows = []
    table_rows.append(["alias", "nixosconfig", "hostname"])
    for alias, host in TARGETS.all().items():
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
    inv print-keys hetzci-release
    """
    target = TARGETS.get(alias)
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


def get_deploy_host(alias: str) -> DeployHost:
    """
    Return DeployHost object, given `alias`
    """
    hostname = TARGETS.get(alias).hostname
    deploy_host = DeployHost(
        host=hostname,
        host_key_check=HostKeyCheck.NONE,
        # verbose_ssh=True,
    )
    return deploy_host


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
                    f"{target.secretspath}",
                ],
                check=True,
                stdout=fh,
            )
        except subprocess.CalledProcessError:
            logger.warning(
                f"Failed reading secret 'ssh_host_ed25519_key' for '{target.nixosconfig}'"
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
def install_release(c: Any) -> None:
    """
    Initialize hetzner release environment

    Example usage:
    inv install-release
    """
    # Install release hosts
    release_hosts = ["hetz86-rel-1", "hetzarm-rel-1", "hetzci-release"]
    for host in release_hosts:
        install(c, host, yes=True)
    # Connect testagent-release to the installed release jenkins controller
    h = get_deploy_host("testagent-release")
    try:
        h.run(cmd="connect https://ci-release.vedenemo.dev", timeout=10)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        logger.info(
            "Failed connecting 'testagent-release' to the installed release environment. "
            "The release environment is otherwise up, but you need to manually connect "
            "the testagent to the release Jenkins instance. "
            f"Hint: is the testagent at '{h.host}' accessible over SSH? "
            "Perhaps you need to connect a VPN?"
        )


@task
def install(c: Any, alias: str, yes: bool = False) -> None:
    """
    Install `alias` configuration using nixos-anywhere, deploying host private key.
    Note: this will automatically partition and re-format the target hard drive,
    meaning all data on the target will be completely overwritten with no option
    to rollback. Option `--yes` allows running the script non-interactively assuming
    "yes" as answer to all prompts.

    Example usage:
    inv install hetzci-release --yes
    """
    h = get_deploy_host(alias)

    if not yes:
        ask = input(f"Install configuration '{alias}'? [y/N] ")
        if ask != "y":
            return

    # Check ssh and remote user
    try:
        remote_user = h.run(cmd="whoami", stdout=subprocess.PIPE).stdout.strip()
        ret = subprocess.run(["whoami"], capture_output=True, text=True, check=True)
        assert ret is not None
        local_user = ret.stdout.strip()
        if not yes and remote_user and local_user and remote_user != local_user:
            logger.warning(
                f"Remote user '{remote_user}' is not your current local user. "
                "You will likely not be able to login to the remote host "
                f"'{TARGETS.get(alias).hostname}' "
                "after nixos-anywhere installation. Consider adding your local "
                f"user to the remote host and make sure user '{local_user}' "
                "also has access to remote host after nixos-anywhere installation "
                "by adding your local user as a user to nixos configuration "
                f"'{TARGETS.get(alias).nixosconfig}'. "
                "Hint: you might want to try the helper script at "
                "'scripts/add-remote-user.sh' to add your current local "
                "user to the remote host."
            )
            ask = input("Still continue? [y/N] ")
            if ask != "y":
                sys.exit(1)
    except subprocess.CalledProcessError:
        logger.error("No ssh access to the remote host")
        sys.exit(1)
    # Check sudo nopasswd
    try:
        h.run("sudo -n true", become_root=True)
    except subprocess.CalledProcessError:
        logger.warning(
            f"sudo on '{h.host}' needs password: installation will likely fail"
        )
        if not yes:
            ask = input("Still continue? [y/N] ")
            if ask != "y":
                sys.exit(1)
    # Check dynamic ip
    try:
        h.run("ip a | grep dynamic")
    except subprocess.CalledProcessError:
        pass
    else:
        logger.warning(f"Above address(es) on '{h.host}' use dynamic addressing.")
        logger.warning(
            "This might cause issues if you assume the target host is reachable "
            "from any such address also after kexec switch. "
            "If you do, consider making the address temporarily static "
            "before continuing."
        )
        if not yes:
            ask = input("Still continue? [y/N] ")
            if ask != "y":
                sys.exit(1)

    target = TARGETS.get(alias)
    with TemporaryDirectory() as tmpdir:
        decrypt_host_key(target, tmpdir)
        command = f"nixos-anywhere {h.host} --extra-files {tmpdir} "
        command += f"--flake .#{target.nixosconfig} --option accept-flake-config true"
        logger.warning(command)
        c.run(command)

    # Reboot
    print(f"Wait for {h.host} to start", end="")
    wait_for_port(h.host, 22)
    reboot(c, alias)


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
    inv reboot hetzci-release
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
def print_revision(_c: Any, alias: str = "") -> None:
    """
    Print the currently deployed git revision on the 'alias' host.
    If 'alias' is not specified, prints deployed revisions on all TARGETS.

    Example usage:
    inv print-revision
    inv print-revision --alias=hetzci-release
    """
    header_row = ["alias", "revision", "revision date", "revision subject"]
    table_rows = []
    target_aliases = [alias]
    git_info = {}
    git_info_map = {"hash": 0, "date": 1, "subj": 2}
    git_info_def = [""] * len(git_info_map)
    delim = "_;_;_;_"
    # Read the following git log info:
    #   %H    - commit hash
    #   %cs   - committer date, short format (YYYY-MM-DD)
    #   %s    - commit subject line
    # Note: We don't fetch remote so the git info might not be fully up-to-date
    cmd = f"git log --pretty=format:'%H{delim}%cs{delim}%s'"
    proc = subprocess.run(cmd, capture_output=True, shell=True, text=True, check=True)
    for line in proc.stdout.splitlines():
        split_line = line.split(delim)
        githash = split_line[git_info_map["hash"]]
        git_info.setdefault(githash, split_line)
    if not alias:
        target_aliases = list(TARGETS.all().keys())
    for target in target_aliases:
        h = get_deploy_host(target)
        try:
            rev = h.run(
                cmd="nixos-version --configuration-revision",
                stdout=subprocess.PIPE,
                timeout=5,
            ).stdout.strip()
            if "-dirty" not in rev:
                # Format as terminal link: https://github.com/Alhadis/OSC8-Adoption/
                url = f"https://github.com/tiiuae/ghaf-infra/commit/{rev}"
                rev_link = f"\033]8;;{url}\033\\{rev}\033]8;;\033\\"
            else:
                rev_link = rev
        except subprocess.TimeoutExpired:
            rev = "(unknown)"
            rev_link = rev
        git_date = git_info.get(rev, git_info_def)[git_info_map["date"]]
        git_subj = git_info.get(rev, git_info_def)[git_info_map["subj"]]
        row = [target, rev_link, git_date, git_subj]
        table_rows.append(row)
    table_rows.sort(reverse=True, key=lambda x: x[2])  # sort by git_date
    table = tabulate(table_rows, headers=header_row, tablefmt="fancy_outline")
    print(f"\nCurrently deployed revision(s):\n\n{table}")


################################################################################


def init() -> None:
    """
    Module initialization
    """
    # Set default logging level to DEBUG
    logger.remove(0)
    logger.add(sys.stderr, level="DEBUG")
    # Init global variables
    global ROOT, TARGETS
    ROOT = Path(__file__).parent.resolve()
    os.chdir(ROOT)
    TARGETS = Targets()


init()
