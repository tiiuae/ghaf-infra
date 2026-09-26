#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
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
# Get help (using 'install' task as an example):
# $ inv --help install
#
# Run a task (using alias-list as an example):
# $ inv alias-list
#
# For more pyinvoke usage examples, see:
# https://docs.pyinvoke.org/en/stable/getting-started.html


"""Misc dev and deployment helper tasks."""

# pylint: disable=too-many-lines

import getpass
import json
import logging
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import time
from collections.abc import Iterable, Iterator
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory, mkdtemp
from typing import Any, TextIO

import yaml
from deploykit import DeployHost, HostKeyCheck
from invoke.context import Context
from invoke.parser.argument import Argument
from invoke.tasks import Task, task
from loguru import logger
from tabulate import tabulate


################################################################################
# Configuration
################################################################################

ROOT, TARGETS = (None, None)
THREAD_LOG_STREAM: ContextVar[TextIO | None] = ContextVar(
    "thread_log_stream", default=None
)
LOGURU_FORMAT = "{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {message}"
LOGURU_COLOR_FORMAT = (
    "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
    "<level>{level: <8}</level> | "
    "<level>{message}</level>"
)

REVISION_DELIM = "\x1f"  # ASCII unit separator — can't appear in commit metadata

NIXOS_IMAGES_URL = "https://github.com/nix-community/nixos-images/releases/download"
KEXEC_IMAGES = {
    "hetz86-rel-2": (
        f"{NIXOS_IMAGES_URL}/nixos-24.05/"
        "nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz"
    ),
    "hetzarm-rel-1": (
        f"{NIXOS_IMAGES_URL}/nixos-26.05/"
        "nixos-kexec-installer-noninteractive-aarch64-linux.tar.gz"
    ),
}

RELEASE_BUILDER_USERS = (
    "hetz86-rel-2-builder",
    "hetzarm-rel-1-builder",
)
RELEASE_BUILDER_ALIASES = (
    "hetz86-rel-2",
    "hetzarm-rel-1",
)
RELEASE_CONTROLLER_ALIAS = "hetzci-release"
RELEASE_HOST_ALIASES = (*RELEASE_BUILDER_ALIASES, RELEASE_CONTROLLER_ALIAS)
RELEASE_BUILDER_CA_PATH = "/var/lib/baseline-reset/release-builder-ca.pub"
RELEASE_CONTROLLER_CREDENTIALS = "/run/release-builder-credentials"
RELEASE_TESTAGENT_ALIAS = "testagent-release"
RELEASE_TESTAGENT_URL = "https://ci-release.vedenemo.dev"
RELEASE_CONNECT_ATTEMPTS = 3
RELEASE_CONNECT_SLEEP_SEC = 5
RELEASE_DEPLOY_SSH_PROBE_TIMEOUT_SEC = 5
REBOOT_SHUTDOWN_TIMEOUT_SEC = 120
REBOOT_START_TIMEOUT_SEC = 600


################################################################################
# Data models
################################################################################


@dataclass(eq=False)
class TargetHost:
    """Represents target host."""

    hostname: str
    nixosconfig: str
    public_key: str | None = None
    secretspath: str | None = None
    secrets_resolved: bool = False


class Targets:
    """Represents all installation targets."""

    def __init__(self, flake: str | None = None) -> None:
        self.flake = flake or str(ROOT)
        self.populated = False
        self.target_dict: OrderedDict[str, TargetHost] = OrderedDict()

    def all(self) -> OrderedDict[str, TargetHost]:
        """Get all hosts."""
        if not self.populated:
            self._populate()
        return self.target_dict

    def _populate(self) -> None:
        """Populate the target dictionary from nix evaluation."""
        _log_debug("Reading targets")
        self.target_dict = OrderedDict(
            {
                name: TargetHost(
                    hostname=node["hostname"],
                    nixosconfig=node["config"],
                    public_key=node.get("publicKey"),
                )
                for name, node in _run_json(
                    ["nix", "eval", "--json", f"{self.flake}#installationTargets"]
                ).items()
            }
        )
        self.populated = True

    def get(self, alias: str) -> TargetHost:
        """Get one host, exiting cleanly on unknown aliases."""
        _log_debug(f"Reading target '{alias}'")
        if not self.populated:
            self._populate()
        if alias not in self.target_dict:
            _log_error(f"Unknown alias '{alias}'")
            sys.exit(1)
        return self.target_dict[alias]

    def resolve_secrets(self, alias: str) -> TargetHost:
        """Populate the secret path for one target on demand."""
        target = self.get(alias)
        if target.secrets_resolved:
            return target

        target.secretspath = _run_json(
            [
                "nix",
                "eval",
                "--json",
                f"{self.flake}#installationTargetSecrets.{alias}",
            ]
        )
        target.secrets_resolved = True
        return target


################################################################################
# Common helpers
################################################################################


class _ContextLoguruHandler(logging.Handler):
    """Forward stdlib log records through loguru."""

    def emit(self, record: logging.LogRecord) -> None:
        """Emit one formatted log record."""
        try:
            level = record.levelname
            message = record.getMessage()
            command_prefix = getattr(record, "command_prefix", "")
            if command_prefix:
                message = f"[{command_prefix}] {message}"
            getattr(_active_logger().opt(exception=record.exc_info), level.lower())(
                message
            )
        except RecursionError:
            raise
        # Logging handlers are expected to swallow formatting/write errors and
        # delegate them to handleError instead of crashing the caller.
        except Exception:  # pylint: disable=broad-exception-caught
            self.handleError(record)


def _configure_context_stream_logger(logger_obj: logging.Logger) -> None:
    """Replace logger stream handlers with a loguru bridge handler."""
    if any(
        isinstance(handler, _ContextLoguruHandler) for handler in logger_obj.handlers
    ):
        return

    handler_level = logger_obj.level

    logger_obj.handlers = [
        handler
        for handler in logger_obj.handlers
        if not isinstance(handler, logging.StreamHandler)
    ]

    handler = _ContextLoguruHandler()
    handler.setLevel(handler_level)
    logger_obj.addHandler(handler)


@contextmanager
def _quiet_deploykit_commands() -> Iterator[None]:
    """Hide routine remote commands while preserving warnings and errors."""
    command_logger = logging.getLogger("deploykit.command")
    previous_level = command_logger.level
    command_logger.setLevel(logging.WARNING)
    try:
        yield
    finally:
        command_logger.setLevel(previous_level)


_configure_context_stream_logger(logging.getLogger("deploykit.command"))
_configure_context_stream_logger(logging.getLogger("deploykit.main"))


def _run_checked(cmd: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    """Run a local command and require success."""
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def _run_json(cmd: list[str]) -> Any:
    """Run a local command that returns JSON, exiting cleanly on failure."""
    try:
        proc = _run_checked(cmd, capture_output=True)
    except subprocess.CalledProcessError as err:
        detail = (err.stderr or "").strip() or str(err)
        _log_error(f"Command failed: {shlex.join(cmd)}\n{detail}")
        sys.exit(1)
    return json.loads(proc.stdout)


def _sops_files_from_config(sops_config: Path) -> list[Path]:
    """Return existing files matched by path_regex entries in a sops config."""
    root = sops_config.parent
    sops_data = yaml.safe_load(sops_config.read_text(encoding="utf-8"))
    path_regexes = [
        re.compile(rule["path_regex"])
        for rule in sops_data["creation_rules"]
        if "path_regex" in rule
    ]

    sops_files = []
    for current_root, dirnames, filenames in os.walk(root):
        dirnames[:] = [dirname for dirname in dirnames if dirname != ".git"]
        for filename in filenames:
            path = Path(current_root) / filename
            relative_path = path.relative_to(root)
            if any(
                path_regex.search(relative_path.as_posix())
                for path_regex in path_regexes
            ):
                sops_files.append(relative_path)

    return sorted(sops_files)


def _current_output_stream() -> TextIO:
    """Return the thread-local output stream when configured."""
    stream = THREAD_LOG_STREAM.get()
    return sys.stdout if stream is None else stream


def _stderr_loguru_sink(message: str) -> None:
    """Write colored loguru messages to the active stderr stream."""
    sys.stderr.write(message)
    sys.stderr.flush()


def _stderr_supports_color() -> bool:
    """Return True when stderr is an interactive stream that can render ANSI."""
    return bool(
        getattr(sys.stderr, "isatty", None)
        and sys.stderr.isatty()
        and os.environ.get("NO_COLOR") is None
    )


def _thread_loguru_sink(message: str) -> None:
    """Write plain loguru messages to the thread-local stream."""
    stream = THREAD_LOG_STREAM.get()
    if stream is None:
        return
    stream.write(message)
    stream.flush()


def _active_logger() -> Any:
    """Return the logger instance for the current execution context."""
    if THREAD_LOG_STREAM.get() is None:
        return logger
    return logger.bind(thread_local_stream=True)


def _log_message(level: str, message: str) -> None:
    """Log via loguru using the configured thread-aware sink."""
    getattr(_active_logger(), level)(message)


def _log_info(message: str) -> None:
    """Log an informational message."""
    _log_message("info", message)


def _log_status_info(message: str) -> None:
    """Log a high-level status message and mirror it to stderr when thread-local."""
    _log_info(message)
    if THREAD_LOG_STREAM.get() is not None:
        logger.info(message)


def _log_debug(message: str) -> None:
    """Log a debug message."""
    _log_message("debug", message)


def _log_warning(message: str) -> None:
    """Log a warning message."""
    _log_message("warning", message)


def _log_error(message: str) -> None:
    """Log an error message."""
    _log_message("error", message)


def _print_output(message: str = "", *, end: str = "\n") -> None:
    """Print to the thread-local stream when configured."""
    print(message, end=end, file=_current_output_stream(), flush=True)


def _confirm(prompt: str, yes: bool) -> bool:
    """Return True when the user confirms or `yes` bypasses the prompt."""
    if yes:
        return True
    return input(prompt) == "y"


def _warn_and_confirm(message: str, yes: bool) -> None:
    """Log a warning and ask the operator to continue."""
    _log_warning(message)
    if THREAD_LOG_STREAM.get() is not None:
        logger.warning(message)
    if not _confirm("Still continue? [y/N] ", yes):
        sys.exit(1)


def _remote_stdout(
    host: DeployHost,
    cmd: str,
    *,
    timeout: int | None = None,
    become_root: bool = False,
    suppress_stderr: bool = False,
) -> str:
    """Run a remote command and return stdout."""
    run_kwargs: dict[str, object] = {
        "cmd": cmd,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE if suppress_stderr else None,
        "become_root": become_root,
    }
    if timeout is not None:
        run_kwargs["timeout"] = timeout
    return host.run(**run_kwargs).stdout.strip()


def _build_target_ref(target: TargetHost, flake: str = ".") -> str:
    """Return the flake output used for local system builds."""
    return (
        f"{flake}#nixosConfigurations.{target.nixosconfig}.config.system.build.toplevel"
    )


def _build_local_build_command(target: TargetHost, flake: str = ".") -> str:
    """Return the `nix build` command string used by invoke."""
    return shlex.join(["nix", "build", "--no-link", _build_target_ref(target, flake)])


def _build_nixos_anywhere_command(
    ssh_target: str,
    tmpdir: str,
    target: TargetHost,
    *,
    kexec_url: str | None = None,
    flake: str = ".",
) -> str:
    """Return the `nixos-anywhere` command string used by invoke."""
    cmd = [
        "nixos-anywhere",
        ssh_target,
        "--extra-files",
        tmpdir,
    ]
    if kexec_url is not None:
        cmd.extend(["--kexec", kexec_url])
    cmd.extend(
        [
            "--flake",
            f"{flake}#{target.nixosconfig}",
            "--option",
            "accept-flake-config",
            "true",
        ]
    )
    return shlex.join(cmd)


def _clone_context(c: Context) -> Context:
    """Return a fresh invoke context with cloned configuration."""
    return Context(config=c.config.clone())


def _clone_context_for_stream(c: Context, stream: TextIO) -> Context:
    """Return a fresh invoke context that writes command output to `stream`."""
    clone = _clone_context(c)
    clone.config.run.out_stream = stream
    clone.config.run.err_stream = stream
    return clone


def _get_deploy_host(
    alias: str,
    user: str | None = None,
    target: TargetHost | None = None,
    *,
    known_hosts: Path | None = None,
) -> DeployHost:
    """Return DeployHost object, given `alias`."""
    hostname = target.hostname if target is not None else TARGETS.get(alias).hostname
    extra_ssh_opts = ["-o", "LogLevel=ERROR"]
    if known_hosts is not None:
        extra_ssh_opts.extend(
            [
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                f"UserKnownHostsFile={known_hosts}",
                "-o",
                "GlobalKnownHostsFile=/dev/null",
            ]
        )
    return DeployHost(
        host=hostname,
        user=user,
        host_key_check=(
            HostKeyCheck.STRICT if known_hosts is not None else HostKeyCheck.NONE
        ),
        extra_ssh_opts=extra_ssh_opts,
        # verbose_ssh=True,
    )


################################################################################
# Secrets helpers
################################################################################


def _decrypt_host_key(
    target: TargetHost,
    tmpdir: str,
    yes: bool,
    host_key_path: str = "/etc/ssh/ssh_host_ed25519_key",
) -> None:
    """Run sops to extract `nixosconfig` secret `ssh_host_ed25519_key`."""

    if target.secretspath is None:
        _log_error(
            f"Missing sops secret path for '{target.nixosconfig}'; cannot decrypt host key"
        )
        sys.exit(1)

    def opener(path: str, flags: int) -> int:
        return os.open(path, flags, 0o400)

    tmpdir_path = Path(tmpdir)
    tmpdir_path.mkdir(parents=True, exist_ok=True)
    tmpdir_path.chmod(0o755)
    destination = Path(host_key_path)
    if not destination.is_absolute() or ".." in destination.parts:
        raise ValueError(f"Invalid SSH host key path: {host_key_path}")
    host_key = tmpdir_path.joinpath(*destination.parts[1:])
    host_key.parent.mkdir(parents=True, exist_ok=True)
    with open(host_key, "w", opener=opener, encoding="utf-8") as fh:
        try:
            _run_checked(
                [
                    "sops",
                    "--extract",
                    '["ssh_host_ed25519_key"]',
                    "--decrypt",
                    f"{target.secretspath}",
                ],
                stdout=fh,
            )
        except subprocess.CalledProcessError:
            _warn_and_confirm(
                f"Failed reading secret 'ssh_host_ed25519_key' for '{target.nixosconfig}'",
                yes,
            )
        else:
            pub_key = Path(f"{host_key}.pub")
            with open(pub_key, "w", encoding="utf-8") as fh:
                _run_checked(
                    ["ssh-keygen", "-y", "-f", f"{host_key}"],
                    stdout=fh,
                )
            pub_key.chmod(0o644)


def _sign_nebula_host_certificate(
    secret_file: Path,
    host_dir: Path,
    ca_key: Path,
    ca_certificate: Path,
) -> tuple[str, Path, Path]:
    """Sign a new Nebula certificate using an existing certificate's details."""
    old_certificate = host_dir / "old.crt"
    new_certificate = host_dir / "host.crt"
    new_key = host_dir / "host.key"
    old_certificate.write_text(
        _run_checked(
            [
                "sops",
                "decrypt",
                "--extract",
                '["nebula-cert"]',
                f"{secret_file}",
            ],
            capture_output=True,
        ).stdout,
        encoding="utf-8",
    )
    details = _run_json(
        ["nebula-cert", "print", "-json", "-path", f"{old_certificate}"]
    )[0]["details"]
    command = [
        "nebula-cert",
        "sign",
        "-ca-key",
        f"{ca_key}",
        "-ca-crt",
        f"{ca_certificate}",
        "-name",
        details["name"],
        "-networks",
        ",".join(details["networks"]),
        "-out-crt",
        f"{new_certificate}",
        "-out-key",
        f"{new_key}",
    ]
    if details["groups"]:
        command.extend(["-groups", ",".join(details["groups"])])
    _run_checked(command)
    return details["name"], new_certificate, new_key


def _replace_nebula_secrets(
    replacements: list[tuple[Path, Path, Path]], tmpdir: Path
) -> None:
    """Replace Nebula certificates and keys in sops files."""
    prepared_files = []
    for index, (secret_file, certificate, key) in enumerate(replacements):
        prepared_file = tmpdir / f"secrets-{index}.yaml"
        shutil.copy2(secret_file, prepared_file)
        for secret_name, value_file in (
            ("nebula-cert", certificate),
            ("nebula-key", key),
        ):
            _run_checked(
                [
                    "sops",
                    "set",
                    "--value-stdin",
                    f"{prepared_file}",
                    f'["{secret_name}"]',
                ],
                input=json.dumps(value_file.read_text(encoding="utf-8")),
            )
        prepared_files.append(prepared_file)

    for (secret_file, _certificate, _key), prepared_file in zip(
        replacements, prepared_files, strict=True
    ):
        prepared_file.replace(secret_file)


################################################################################
# Install helpers
################################################################################


def _assert_stateversion(
    alias: str, host: str, yes: bool, flake: str | None = None
) -> None:
    """Assert that stateVersion matches nixpkgs version."""
    flake = flake or f"git+file://{ROOT}"
    ret = subprocess.run(
        [
            "nix",
            "eval",
            "--impure",
            "--json",
            "--expr",
            f"let \
                flake = builtins.getFlake {json.dumps(flake)}; \
                host = flake.nixosConfigurations.{host}; \
                nixpkgsVersion = builtins.substring 0 5 host.lib.version; \
                stateVersion = host.config.system.stateVersion; \
              in {{ inherit stateVersion nixpkgsVersion; }}",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        ret.check_returncode()
    except subprocess.CalledProcessError:
        _log_error(ret.stderr)
        sys.exit(1)

    version_data = json.loads(ret.stdout)
    state_version = version_data["stateVersion"]
    nixpkgs_version = version_data["nixpkgsVersion"]
    if state_version != nixpkgs_version:
        _warn_and_confirm(
            f"Attempting to install {alias} with nixpkgs version "
            f"'{nixpkgs_version}' but `{host}.config.system.stateVersion` is "
            f"'{state_version}'. stateVersion should be bumped to match "
            "installation state!",
            yes,
        )


def _check_remote_user_alignment(
    target: TargetHost,
    host: DeployHost,
    user: str | None,
    yes: bool,
) -> None:
    """Warn when the remote login user differs from the local user."""
    try:
        remote_user = _remote_stdout(host, "whoami")
    except subprocess.CalledProcessError:
        _log_error("No ssh access to the remote host")
        sys.exit(1)

    local_user = getpass.getuser()
    if (
        yes
        or user is not None
        or not remote_user
        or not local_user
        or remote_user == local_user
    ):
        return

    _warn_and_confirm(
        f"Remote user '{remote_user}' is not your current local user. "
        "You will likely not be able to login to the remote host "
        f"'{target.hostname}' "
        "after nixos-anywhere installation. Consider adding your local "
        f"user to the remote host and make sure user '{local_user}' "
        "also has access to remote host after nixos-anywhere installation "
        "by adding your local user as a user to nixos configuration "
        f"'{target.nixosconfig}'. "
        "Hint: you might want to try the helper script at "
        "'scripts/add-remote-user.sh' to add your current local "
        "user to the remote host.",
        yes,
    )


def _check_remote_sudo(host: DeployHost, yes: bool) -> None:
    """Warn when passwordless sudo is unavailable on the target."""
    try:
        host.run("sudo -n true", become_root=True)
    except subprocess.CalledProcessError:
        _warn_and_confirm(
            f"sudo on '{host.host}' needs password: installation will likely fail",
            yes,
        )


################################################################################
# Release-install helpers
################################################################################


def _generate_release_ssh_ca(tmpdir: Path) -> Path:
    """Generate a temporary SSH CA used during release installation."""
    ca = tmpdir / "ca/ssh_user_ca"
    ca.parent.mkdir(parents=True, exist_ok=True)
    _run_checked(
        ["ssh-keygen", "-f", f"{ca}", "-C", "", "-N", ""],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return ca


def _generate_signed_user_key(ca: Path, tmpdir: Path, user: str) -> Path:
    """Generate and sign a controller SSH key for one release builder user."""
    key = tmpdir / f"controller/etc/ssh/certs/{user}"
    key.parent.mkdir(parents=True, exist_ok=True)
    _run_checked(
        ["ssh-keygen", "-f", f"{key}", "-C", "", "-N", ""],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    _run_checked(
        ["ssh-keygen", "-s", f"{ca}", "-I", "", "-n", f"{user}", f"{key}.pub"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return key


def _new_install_log_path(alias: str, prefix: str = "install-logs-") -> Path:
    """
    Return a fresh per-host log file path for one install workflow.

    The parent temporary directory is intentionally left on disk so operators can
    inspect install logs after success or failure; callers do not clean it up.
    """
    return Path(mkdtemp(prefix=prefix)) / f"{alias}.log"


def _announce_install_log_path(alias: str, log_path: Path) -> None:
    """Log where one install writes its detailed output."""
    logger.info(f"Writing install log for '{alias}' to {log_path}")


@contextmanager
def _thread_log_to_file(log_path: Path) -> Iterator[TextIO]:
    """Route thread-local log and print output to `log_path`."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w", encoding="utf-8") as stream:
        token = THREAD_LOG_STREAM.set(stream)
        try:
            yield stream
        finally:
            THREAD_LOG_STREAM.reset(token)


def _install_error_summary(err: Exception | SystemExit) -> str:
    """Return a compact single-line summary for one install failure."""
    detail = next((line.strip() for line in str(err).splitlines() if line.strip()), "")
    return f"{type(err).__name__}: {detail}" if detail else type(err).__name__


def _release_flake_ref(enabled: bool) -> str | None:
    """Return the current clean Git revision as an immutable flake reference."""
    if not enabled:
        return None
    if _run_checked(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        capture_output=True,
    ).stdout:
        raise RuntimeError("install-release requires a clean tracked checkout")
    revision = _run_checked(
        ["git", "rev-parse", "HEAD"], capture_output=True
    ).stdout.strip()
    return f"git+{ROOT.as_uri()}?rev={revision}"


def _install_release_hosts(c: Context, flake: str) -> None:
    """Install all release hosts using the public install task."""
    _log_info(f"Installing {len(RELEASE_HOST_ALIASES)} release host(s) in parallel")

    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=len(RELEASE_HOST_ALIASES)) as executor:
        future_to_alias = {
            executor.submit(
                _install_with_log,
                _clone_context(c),
                alias,
                yes=True,
                flake=flake,
            ): alias
            for alias in RELEASE_HOST_ALIASES
        }
        for future in as_completed(future_to_alias):
            alias = future_to_alias[future]
            try:
                future.result()
            # Worker installs may raise SystemExit via helper guards; keep going so
            # all parallel host failures are surfaced before the task aborts.
            except (Exception, SystemExit) as err:  # pylint: disable=broad-exception-caught
                failures.append(alias)
                detail = _install_error_summary(err)
                _log_error(f"Release install failed for '{alias}': {detail}")

    if failures:
        raise RuntimeError(
            f"Release install failed on {len(failures)} host(s): {', '.join(failures)}"
        )


def _prepare_release_baselines(
    reinstall: bool,
    flake: str | None,
    hosts: dict[str, DeployHost],
) -> dict[str, str]:
    """Deploy new baselines and record the systems the reset must select."""
    if flake is not None:
        _log_status_info("Preparing ci-release host baselines")
        expected = {
            alias: _expected_release_system(alias, flake)
            for alias in RELEASE_HOST_ALIASES
        }
        if not reinstall:
            _run_checked(
                [
                    "deploy",
                    "--boot",
                    "--targets",
                    *(f"{flake}#{alias}" for alias in RELEASE_HOST_ALIASES),
                ]
            )
        return expected

    _log_status_info("Reading current ci-release host baselines")
    expected = {}
    for alias in RELEASE_HOST_ALIASES:
        host = hosts[alias]
        booted = _remote_stdout(host, "readlink -f /run/booted-system", timeout=20)
        profile = _remote_stdout(
            host, "readlink -f /nix/var/nix/profiles/system", timeout=20
        )
        if booted != profile:
            raise RuntimeError(
                f"'{alias}' booted {booted}, but its selected system is {profile}; "
                "reboot it or deploy a baseline before using --no-deploy"
            )
        expected[alias] = booted
    return expected


def _preflight_release_reset(hosts: dict[str, DeployHost]) -> None:
    """Require the baseline-reset disk layout."""
    _log_status_info("Checking ci-release reset prerequisites")
    paths = ("/", "/nix", "/var/lib/baseline-reset", "/boot")
    expected = ["btrfs /@root", "btrfs /@nix", "btrfs /@persist", "vfat /"]
    for alias in RELEASE_HOST_ALIASES:
        layout = _remote_stdout(
            hosts[alias],
            f"for path in {shlex.join(paths)}; do "
            'findmnt -nro FSTYPE,FSROOT --mountpoint "$path" || echo missing; '
            "done",
            timeout=20,
        ).splitlines()
        if layout != expected:
            observed = ", ".join(
                f"{path}={value}" for path, value in zip(paths, layout, strict=True)
            )
            raise RuntimeError(
                f"'{alias}' is not reset-ready: expected the baseline-reset disk "
                f"layout, observed {observed}. Inspect the host and rerun with "
                "'inv install-release --reinstall' only if repartitioning is intended"
            )


def _copy_release_file(
    host: DeployHost,
    source: Path,
    destination: str,
    mode: str,
    owner: str,
) -> None:
    """Copy one generated credential and install it atomically."""
    if host.host_key_check != HostKeyCheck.STRICT:
        raise ValueError("Release credentials require a pinned SSH host key")

    remote = _remote_stdout(
        host,
        "path=$(mktemp /run/install-release.XXXXXXXX) && "
        'chown "${SUDO_USER:-root}" "$path" && printf "%s\\n" "$path"',
        timeout=20,
        become_root=True,
    )
    target = f"{host.user}@{host.host}" if host.user else host.host
    command = [
        "scp",
        "-q",
    ]
    if host.port:
        command.extend(["-P", str(host.port)])
    if host.key:
        command.extend(["-i", host.key])
    command.extend(host.extra_ssh_opts)
    command.extend([str(source), f"{target}:{remote}"])
    try:
        _run_checked(command, timeout=20)
        incoming = f"{destination}.new"
        host.run(
            f"install -o {shlex.quote(owner)} -g root -m {shlex.quote(mode)} "
            f"{shlex.quote(remote)} {shlex.quote(incoming)} && "
            f"sync {shlex.quote(incoming)} && "
            f"mv -T {shlex.quote(incoming)} {shlex.quote(destination)} && "
            f"sync -f {shlex.quote(str(Path(destination).parent))}",
            become_root=True,
            timeout=20,
        )
    finally:
        host.run(
            ["rm", "-f", remote],
            become_root=True,
            check=False,
            timeout=20,
        )


def _expected_release_system(alias: str, flake: str) -> str:
    """Evaluate one release host's NixOS toplevel from a pinned flake."""
    return _run_checked(
        [
            "nix",
            "eval",
            "--raw",
            f"{flake}#nixosConfigurations.{alias}.config.system.build.toplevel",
        ],
        capture_output=True,
    ).stdout.strip()


def _verify_release_hosts(
    previous_boot_ids: dict[str, str],
    expected_systems: dict[str, str],
    hosts: dict[str, DeployHost],
) -> None:
    """Require fresh boots into the selected release systems."""
    _log_status_info("Verifying ci-release host baselines")
    for alias in RELEASE_HOST_ALIASES:
        host = hosts[alias]
        boot_id = _remote_stdout(
            host, "cat /proc/sys/kernel/random/boot_id", timeout=20
        )
        if alias in previous_boot_ids and boot_id == previous_boot_ids[alias]:
            raise RuntimeError(f"'{alias}' did not reboot")
        booted = _remote_stdout(host, "readlink -f /run/booted-system", timeout=20)
        expected = expected_systems[alias]
        if booted != expected:
            raise RuntimeError(
                f"'{alias}' booted {booted}, expected {expected}; check its boot deployment"
            )


def _reboot_release_hosts(hosts: dict[str, DeployHost]) -> None:
    """Reset release hosts, bypassing slow PXE probing on the x86 builder."""
    alias = "hetz86-rel-2"
    _log_status_info(f"[{alias}] reboot: selecting the current EFI entry for next boot")
    hosts[alias].run(
        [
            "sh",
            "-c",
            "current=$(efibootmgr | sed -n 's/^BootCurrent: //p') && "
            'test -n "$current" && exec efibootmgr --bootnext "$current"',
        ],
        become_root=True,
        timeout=20,
    )
    _reboot_hosts(
        list(RELEASE_HOST_ALIASES),
        "Reset all three ci-release hosts",
        hosts,
        parallel=True,
    )


def _provision_release_credentials(tmpdir: Path, hosts: dict[str, DeployHost]) -> None:
    """Rotate builder trust and install volatile controller credentials."""
    ca = _generate_release_ssh_ca(tmpdir)
    ca_pub = Path(f"{ca}.pub")
    keys = [
        _generate_signed_user_key(ca, tmpdir, user) for user in RELEASE_BUILDER_USERS
    ]
    ca.unlink()

    for alias in RELEASE_BUILDER_ALIASES:
        _copy_release_file(
            hosts[alias],
            ca_pub,
            RELEASE_BUILDER_CA_PATH,
            "0644",
            "root",
        )

    controller = hosts[RELEASE_CONTROLLER_ALIAS]
    for key in keys:
        destination = f"{RELEASE_CONTROLLER_CREDENTIALS}/{key.name}"
        _copy_release_file(controller, key, destination, "0400", "jenkins")
        _copy_release_file(
            controller,
            Path(f"{key}-cert.pub"),
            f"{destination}-cert.pub",
            "0444",
            "jenkins",
        )

    for alias, user in zip(RELEASE_BUILDER_ALIASES, RELEASE_BUILDER_USERS, strict=True):
        key = f"{RELEASE_CONTROLLER_CREDENTIALS}/{user}"
        store = f"ssh-ng://{user}@{alias}?trusted=true&ssh-key={key}"
        try:
            controller.run(
                [
                    "runuser",
                    "-u",
                    "jenkins",
                    "--",
                    "env",
                    "HOME=/var/lib/jenkins",
                    "PATH=/run/current-system/sw/bin",
                    "nix",
                    "store",
                    "info",
                    "--store",
                    store,
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                become_root=True,
                timeout=20,
            )
        except subprocess.CalledProcessError as err:
            detail = (err.stderr or err.stdout or "").strip() or str(err)
            raise RuntimeError(
                f"Release builder store check failed for '{alias}': {detail}"
            ) from err
    controller.run(
        ["systemctl", "start", "jenkins.service"],
        become_root=True,
        timeout=180,
    )


def _deploy_release_testagent(c: Context, host: DeployHost, flake: str) -> bool:
    """Deploy the release testagent without reinstalling it."""
    port = host.port or 22
    if not _can_connect(host.host, port, timeout=RELEASE_DEPLOY_SSH_PROBE_TIMEOUT_SEC):
        _log_status_info(
            "Failed deploying 'testagent-release'. "
            "The release environment is otherwise up, but you should manually deploy "
            "the testagent-release, then connect it to the release Jenkins instance. "
            f"Hint: could not reach '{host.host}:{port}' over TCP within "
            f"{RELEASE_DEPLOY_SSH_PROBE_TIMEOUT_SEC}s. "
            "Perhaps you need to connect a VPN?"
        )
        return False

    deploy = c.run(
        shlex.join(["deploy", "-s", "--targets", f"{flake}#{RELEASE_TESTAGENT_ALIAS}"]),
        warn=True,
    )
    if deploy.ok:
        return True

    _log_status_info(
        "Failed deploying 'testagent-release'. "
        "The release environment is otherwise up, but you should manually deploy "
        "the testagent-release, then connect it to the release Jenkins instance. "
        f"Hint: is the testagent at '{host.host}' accessible over SSH? "
        "Perhaps you need to connect a VPN?"
    )
    return False


def _connect_release_testagent(host: DeployHost) -> bool:
    """Try to connect the release testagent to the Jenkins controller."""
    command = shlex.join(["connect", RELEASE_TESTAGENT_URL])
    for attempt in range(RELEASE_CONNECT_ATTEMPTS):
        try:
            host.run(cmd=command, timeout=20)
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            if attempt + 1 == RELEASE_CONNECT_ATTEMPTS:
                return False
            time.sleep(RELEASE_CONNECT_SLEEP_SEC)
    return False


@contextmanager
def _pinned_release_hosts(targets: Targets) -> Iterator[dict[str, DeployHost]]:
    """Return release hosts pinned to the public keys in the target inventory."""
    aliases = (*RELEASE_HOST_ALIASES, RELEASE_TESTAGENT_ALIAS)
    release_targets = {alias: targets.get(alias) for alias in aliases}
    missing_keys = [
        alias for alias, target in release_targets.items() if target.public_key is None
    ]
    if missing_keys:
        raise RuntimeError(
            "Missing pinned SSH host key for release target(s): "
            + ", ".join(missing_keys)
        )

    with TemporaryDirectory() as ssh_dir:
        known_hosts = Path(ssh_dir) / "known_hosts"
        known_hosts.write_text(
            "".join(
                f"{target.hostname} {target.public_key}\n"
                for target in release_targets.values()
            ),
            encoding="utf-8",
        )
        yield {
            alias: _get_deploy_host(
                alias,
                target=release_targets[alias],
                known_hosts=known_hosts,
            )
            for alias in aliases
        }


################################################################################
# Reporting helpers
################################################################################


def _can_connect(host: str, port: int, timeout: int | float = 1) -> bool:
    """Return True when a TCP connection can be established within `timeout`."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _wait_for_port(
    host: str,
    port: int,
    shutdown: bool = False,
    timeout: int | float | None = None,
) -> bool:
    """Wait for `host`:`port`."""
    deadline = time.monotonic() + timeout if timeout is not None else None
    while True:
        time.sleep(1)
        if _can_connect(host, port):
            if not shutdown:
                return True
        elif shutdown:
            return True
        if deadline is not None and time.monotonic() >= deadline:
            return False


def _git_revision_info(revisions: Iterable[str] | None = None) -> dict[str, list[str]]:
    """Read local git metadata used to annotate deployed revisions."""
    cmd = ["git", "log", f"--pretty=format:%H{REVISION_DELIM}%cs{REVISION_DELIM}%s"]
    if revisions is not None:
        unique_revisions = list(dict.fromkeys(revisions))
        if not unique_revisions:
            return {}
        cmd.insert(2, "--ignore-missing")
        cmd.insert(2, "--no-walk")
        cmd.extend(unique_revisions)

    proc = _run_checked(cmd, capture_output=True)
    git_info: dict[str, list[str]] = {}
    for line in proc.stdout.splitlines():
        split_line = line.split(REVISION_DELIM)
        git_info[split_line[0]] = split_line
    return git_info


def _read_deployed_revision(target_alias: str) -> tuple[str, str, str]:
    """Read the currently deployed revision and reboot state from one target host."""
    host = _get_deploy_host(target_alias)
    command = """
revision="$(nixos-version --configuration-revision 2>/dev/null || true)"
[ -n "$revision" ] || revision="(unknown)"
printf '%s\\n' "$revision"

booted="$(readlink \
  /run/booted-system/initrd \
  /run/booted-system/kernel \
  /run/booted-system/kernel-modules 2>/dev/null)" &&
current="$(readlink \
  /run/current-system/initrd \
  /run/current-system/kernel \
  /run/current-system/kernel-modules 2>/dev/null)" || {
  printf '%s\\n' "(unknown)"
  exit 0
}

if [ "$booted" = "$current" ]; then
  printf '%s\\n' "no"
else
  printf '%s\\n' "yes"
fi
""".strip()
    try:
        lines = _remote_stdout(
            host,
            command,
            timeout=5,
            suppress_stderr=True,
        ).splitlines()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return target_alias, "(unknown)", "(unknown)"

    revision = lines[0] if lines else "(unknown)"
    reboot_needed = lines[1] if len(lines) > 1 else "(unknown)"
    if reboot_needed not in {"yes", "no", "(unknown)"}:
        reboot_needed = "(unknown)"
    return target_alias, revision, reboot_needed


def _read_deployed_revisions(
    target_aliases: Iterable[str],
) -> list[tuple[str, str, str]]:
    """Read deployed revision state from multiple target hosts."""
    aliases = list(target_aliases)
    if not aliases:
        return []

    _log_info(f"Probing {len(aliases)} host(s) (up to 5s each)")
    command_logger = logging.getLogger("deploykit.command")
    command_logger_disabled = command_logger.disabled
    command_logger.disabled = True
    try:
        with ThreadPoolExecutor(max_workers=min(32, len(aliases))) as executor:
            return list(executor.map(_read_deployed_revision, aliases))
    finally:
        command_logger.disabled = command_logger_disabled


def _format_revision_link(rev: str) -> str:
    """Format a revision as a terminal hyperlink when applicable."""
    if rev == "(unknown)":
        return rev
    if rev.endswith("-dirty"):
        return f"{rev.removesuffix('-dirty')[:12]}-dirty"

    # Format as terminal link: https://github.com/Alhadis/OSC8-Adoption/
    url = f"https://github.com/tiiuae/ghaf-infra/commit/{rev}"
    return f"\033]8;;{url}\033\\{rev[:12]}\033]8;;\033\\"


################################################################################
# Invoke tasks
################################################################################


@task
def alias_list(_c: Context) -> None:
    """
    List available targets (i.e. configurations and alias names)

    Example usage:
    inv alias-list
    """
    table_rows = [["alias", "nixosconfig", "host address"]]
    for alias, host in TARGETS.all().items():
        table_rows.append([alias, host.nixosconfig, host.hostname])
    table = tabulate(table_rows, headers="firstrow", tablefmt="fancy_outline")
    _print_output(f"\nCurrent ghaf-infra targets:\n\n{table}")


@task
def update_sops_files(c: Context) -> None:
    """
    Update all sops files according to .sops.yaml rules.

    Example usage:
    inv update-sops-files
    """
    for sops_file in _sops_files_from_config(Path(".sops.yaml")):
        c.run(f"sops updatekeys --yes {shlex.quote(sops_file.as_posix())}")


@task
def renew_nebula_certificates(_c: Context, aliases: str = "") -> None:
    """
    Renew Nebula host certificates and keys stored in sops.

    Example usage:
    inv renew-nebula-certificates
    inv renew-nebula-certificates --aliases ghaf-lighthouse,ghaf-monitoring
    """
    if aliases:
        secret_files = []
        for alias in aliases.split(","):
            store_path = Path(TARGETS.resolve_secrets(alias.strip()).secretspath)
            secret_files.append(
                ROOT.joinpath(*store_path.parts[store_path.parts.index("hosts") :])
            )
    else:
        secret_files = sorted(
            ROOT / path
            for path in _sops_files_from_config(ROOT / ".sops.yaml")
            if re.search(
                r"^nebula-cert:",
                (ROOT / path).read_text(encoding="utf-8"),
                re.MULTILINE,
            )
        )

    with TemporaryDirectory(prefix=".nebula-", dir=ROOT) as tmpdir_name:
        tmpdir = Path(tmpdir_name)
        ca_key = tmpdir / "ca.key"
        ca_bundle = tmpdir / "ca-bundle.crt"
        ca_key.write_text(
            _run_checked(
                ["sops", "decrypt", f"{ROOT}/modules/nebula/ca.key.crypt"],
                capture_output=True,
            ).stdout,
            encoding="utf-8",
        )
        ca_bundle.write_text(
            _run_checked(
                ["sops", "decrypt", f"{ROOT}/modules/nebula/ca.crt.crypt"],
                capture_output=True,
            ).stdout,
            encoding="utf-8",
        )
        signing_ca = tmpdir / "signing-ca.crt"
        signing_ca.write_text(
            re.findall(
                r"-----BEGIN NEBULA CERTIFICATE(?: V2)?-----.*?"
                r"-----END NEBULA CERTIFICATE(?: V2)?-----",
                ca_bundle.read_text(encoding="utf-8"),
                re.DOTALL,
            )[-1]
            + "\n",
            encoding="utf-8",
        )

        replacements = []
        for secret_file in secret_files:
            host_dir = tmpdir / f"host-{len(replacements)}"
            host_dir.mkdir()
            name, new_certificate, new_key = _sign_nebula_host_certificate(
                secret_file, host_dir, ca_key, signing_ca
            )
            replacements.append((secret_file, new_certificate, new_key))
            _log_info(f"Prepared {name} ({secret_file.relative_to(ROOT)})")

        _replace_nebula_secrets(replacements, tmpdir)

    _log_info(f"Updated {len(secret_files)} Nebula host certificate(s)")


@task
def print_keys(_c: Context, alias: str) -> None:
    """
    Decrypt host private key, print ssh and age public keys for `alias` config.

    Example usage:
    inv print-keys hetzci-release
    """
    target = TARGETS.resolve_secrets(alias)
    with TemporaryDirectory() as tmpdir:
        _decrypt_host_key(target, tmpdir, yes=False)
        pub_key = Path(tmpdir) / "etc/ssh/ssh_host_ed25519_key.pub"
        pub_data = pub_key.read_text(encoding="utf-8")
        _print_output("###### Public keys ######")
        _print_output(pub_data)
        _print_output("###### Age keys ######")
        _run_checked(["ssh-to-age"], input=pub_data)


def _run_release_install(c: Context, reinstall: bool, flake: str | None) -> None:
    """Run the release workflow against one pinned flake snapshot."""
    _log_status_info("Preparing ci-release targets")
    targets = Targets(flake) if flake else TARGETS
    with _pinned_release_hosts(targets) as hosts:
        with _quiet_deploykit_commands():
            if not reinstall:
                _preflight_release_reset(hosts)
            expected_systems = _prepare_release_baselines(reinstall, flake, hosts)

            # Stop Jenkins before revoking the previous builder CA, then record boot IDs.
            _log_status_info("Preparing ci-release hosts for reset")
            previous_boot_ids: dict[str, str] = {}
            for alias in (RELEASE_CONTROLLER_ALIAS, *RELEASE_BUILDER_ALIASES):
                if alias == RELEASE_CONTROLLER_ALIAS:
                    command = ["systemctl", "stop", "jenkins.service"]
                else:
                    command = ["rm", "-f", RELEASE_BUILDER_CA_PATH]
                    if reinstall:
                        command.append("/etc/ssh/keys/ssh_user_ca.pub")
                try:
                    hosts[alias].run(
                        command,
                        become_root=True,
                        timeout=120 if alias == RELEASE_CONTROLLER_ALIAS else 20,
                    )
                    previous_boot_ids[alias] = _remote_stdout(
                        hosts[alias], "cat /proc/sys/kernel/random/boot_id", timeout=20
                    )
                except (
                    subprocess.CalledProcessError,
                    subprocess.TimeoutExpired,
                ) as err:
                    if not reinstall:
                        raise
                    _log_warning(
                        f"[{alias}] could not prepare for reset or read the boot ID: "
                        f"{_install_error_summary(err)}"
                    )

        if reinstall:
            assert flake is not None
            _install_release_hosts(c, flake)
        else:
            with _quiet_deploykit_commands():
                _reboot_release_hosts(hosts)

        with _quiet_deploykit_commands():
            _verify_release_hosts(previous_boot_ids, expected_systems, hosts)
            _log_status_info("Provisioning release builder credentials")
            with TemporaryDirectory() as tmpdir_name:
                _provision_release_credentials(Path(tmpdir_name), hosts)
            _log_status_info("Provisioned release builder credentials")

        host = hosts[RELEASE_TESTAGENT_ALIAS]
        log_path = _new_install_log_path(
            RELEASE_TESTAGENT_ALIAS, "install-release-logs-"
        )
        _announce_install_log_path(RELEASE_TESTAGENT_ALIAS, log_path)
        with _thread_log_to_file(log_path) as stream:
            logged_context = _clone_context_for_stream(c, stream)
            if flake is not None:
                _log_status_info(f"[{RELEASE_TESTAGENT_ALIAS}] deploy: starting")
                if not _deploy_release_testagent(logged_context, host, flake):
                    return
            _log_status_info(
                f"[{RELEASE_TESTAGENT_ALIAS}] connect: attaching to "
                f"{RELEASE_TESTAGENT_URL}"
            )
            if _connect_release_testagent(host):
                _log_status_info(f"[{RELEASE_TESTAGENT_ALIAS}] connect: finished")
                return
            _log_status_info(
                "Failed connecting 'testagent-release' to the installed release "
                "environment. The release environment is otherwise up, but you need "
                "to manually connect the testagent to the release Jenkins instance. "
                f"Hint: is the testagent at '{host.host}' accessible over SSH? "
                "Perhaps you need to connect a VPN?"
            )


@task
def install_release(c: Context, reinstall: bool = False, deploy: bool = True) -> None:
    """
    Deploy and reset release hosts; reinstall only for disk layout changes.

    Example usage:
    inv install-release
    inv install-release --no-deploy
    inv install-release --reinstall
    """
    if reinstall and not deploy:
        _log_error("--no-deploy cannot be used with --reinstall")
        sys.exit(1)

    _run_release_install(c, reinstall, _release_flake_ref(deploy))


def _install_with_log(
    c: Context,
    alias: str,
    user: str | None = None,
    yes: bool = False,
    *,
    flake: str | None = None,
) -> None:
    """Run one install with its detailed output routed to a host log."""
    log_path = _new_install_log_path(alias)
    _announce_install_log_path(alias, log_path)
    try:
        with _thread_log_to_file(log_path) as stream:
            _run_install(
                _clone_context_for_stream(c, stream),
                alias,
                user=user,
                yes=yes,
                flake=flake,
            )
    # Top-level installs should still surface a concise terminal summary while
    # keeping the detailed command output in the host log file.
    except (Exception, SystemExit) as err:
        detail = _install_error_summary(err)
        _log_error(f"Install failed for '{alias}': {detail}")
        _log_error(f"See detailed install log: {log_path}")
        raise


@task
def install(
    c: Context,
    alias: str,
    user: str | None = None,
    yes: bool = False,
) -> None:
    """
    Install `alias` configuration using nixos-anywhere, deploying host private key.
    Note: this will automatically partition and re-format the target hard drive,
    meaning all data on the target will be completely overwritten with no option
    to rollback. Option `--yes` allows running the script non-interactively assuming
    "yes" as answer to all prompts.

    Example usage:
    inv install hetzci-release --yes
    """
    _install_with_log(c, alias, user=user, yes=yes)


def _run_install(
    c: Context,
    alias: str,
    user: str | None = None,
    yes: bool = False,
    *,
    flake: str | None = None,
) -> None:
    """Execute the install workflow; see `install` for the user-facing docs."""
    _log_status_info(f"[{alias}] install: starting")
    if not _confirm(f"Install configuration '{alias}'? [y/N] ", yes):
        _log_status_info(f"[{alias}] install: cancelled")
        return

    target = (Targets(flake) if flake else TARGETS).resolve_secrets(alias)
    host = _get_deploy_host(alias, user, target)

    _log_status_info(f"[{alias}] install: validating target and remote access")
    _assert_stateversion(alias, target.nixosconfig, yes, flake)
    _check_remote_user_alignment(target, host, user, yes)
    _check_remote_sudo(host, yes)

    _log_status_info(f"[{alias}] install: building target system locally")
    c.run(_build_local_build_command(target, flake or "."))

    with TemporaryDirectory() as tmpdir:
        _log_status_info(f"[{alias}] install: preparing installer files")
        host_keys = _run_json(
            [
                "nix",
                "eval",
                "--json",
                f"{flake or ROOT}#nixosConfigurations.{target.nixosconfig}"
                ".config.services.openssh.hostKeys",
            ]
        )
        ed25519_host_keys = [
            key["path"] for key in host_keys if key.get("type") == "ed25519"
        ]
        if len(ed25519_host_keys) != 1:
            _log_error(
                f"Expected exactly one ed25519 SSH host key for "
                f"'{target.nixosconfig}', found {len(ed25519_host_keys)}"
            )
            sys.exit(1)
        _decrypt_host_key(target, tmpdir, yes, ed25519_host_keys[0])
        ssh_target = f"{host.user}@{host.host}" if host.user is not None else host.host
        command = _build_nixos_anywhere_command(
            ssh_target,
            tmpdir,
            target,
            kexec_url=KEXEC_IMAGES.get(alias),
            flake=flake or ".",
        )
        _log_status_info(f"[{alias}] install: running nixos-anywhere")
        _log_warning(command)
        c.run(command)

    _log_status_info(f"[{alias}] install: waiting for SSH on {host.host}")
    _wait_for_port(host.host, 22)
    _log_status_info(f"[{alias}] install: rebooting to finalize")
    if not _reboot_host(alias, _get_deploy_host(alias, target=target)):
        sys.exit(1)
    _log_status_info(f"[{alias}] install: finished")


class _ConditionalRebootAliasArgument(Argument):
    """Allow reboot's positional alias to be omitted for alternate modes."""

    optional_when: list[Argument]

    @property
    def value(self) -> Any:
        if self._value is not None:
            return self._value
        if any(arg.value for arg in self.optional_when):
            return ""
        return None

    @value.setter
    def value(self, value: str) -> None:
        self.set_value(value, cast=True)


class _RebootTask(Task):
    """Invoke task variant for reboot's optional alternate modes."""

    def get_arguments(self, ignore_unknown_help: bool | None = None) -> list[Argument]:
        arguments = super().get_arguments(ignore_unknown_help=ignore_unknown_help)
        args_by_name = {arg.name: arg for arg in arguments}
        alias_arg = args_by_name["alias"]
        reboot_alias_arg = _ConditionalRebootAliasArgument(
            names=alias_arg.names,
            kind=alias_arg.kind,
            default=alias_arg.default,
            help=alias_arg.help,
            positional=alias_arg.positional,
            optional=alias_arg.optional,
            incrementable=alias_arg.incrementable,
            attr_name=alias_arg.attr_name,
        )
        reboot_alias_arg.optional_when = [
            args_by_name["needs_reboot"],
            args_by_name["aliases"],
        ]
        arguments[arguments.index(alias_arg)] = reboot_alias_arg
        return arguments


@task(klass=_RebootTask, positional=["alias"])
def reboot(
    _c: Context,
    alias: str = "",
    aliases: str = "",
    needs_reboot: bool = False,
    yes: bool = False,
) -> None:
    """
    Reboot host identified as `alias`, selected aliases, or hosts needing reboot.

    Example usage:
    inv reboot hetzci-release
    inv reboot --aliases hetzci-release,hetzci-dbg
    inv reboot --needs-reboot --yes
    """
    if needs_reboot:
        if alias or aliases:
            _log_error("Use --needs-reboot, an alias, or --aliases, not a mix")
            sys.exit(1)

        target_aliases = [
            target_alias
            for target_alias, _revision, reboot_needed in _read_deployed_revisions(
                TARGETS.all()
            )
            if reboot_needed == "yes"
        ]
        if not target_aliases:
            _log_status_info("No hosts need reboot")
            return

        target_list = ", ".join(target_aliases)
        if not _confirm(
            f"Reboot {len(target_aliases)} host(s) needing reboot: "
            f"{target_list}? [y/N] ",
            yes,
        ):
            _log_status_info("reboot: cancelled")
            return

        _reboot_hosts(
            target_aliases,
            f"Rebooted {len(target_aliases)} host(s) needing reboot",
        )
        return

    if aliases:
        if alias:
            _log_error("Use either an alias or --aliases, not both")
            sys.exit(1)

        target_aliases = list(
            dict.fromkeys(
                target_alias.strip()
                for target_alias in aliases.split(",")
                if target_alias.strip()
            )
        )
        if not target_aliases:
            _log_error("--aliases must include at least one alias")
            sys.exit(1)

        for target_alias in target_aliases:
            TARGETS.get(target_alias)

        target_list = ", ".join(target_aliases)
        if len(target_aliases) > 1 and not _confirm(
            f"Reboot {len(target_aliases)} host(s): {target_list}? [y/N] ",
            yes,
        ):
            _log_status_info("reboot: cancelled")
            return

        _reboot_hosts(target_aliases, f"Rebooted {len(target_aliases)} host(s)")
        return

    if not alias:
        _log_error("Alias is required unless --needs-reboot is set")
        sys.exit(1)

    if not _reboot_host(alias):
        sys.exit(1)


def _reboot_hosts(
    target_aliases: list[str],
    success_message: str,
    hosts: dict[str, DeployHost] | None = None,
    *,
    parallel: bool = False,
) -> None:
    """Reboot multiple target hosts and exit with a summary on failure."""

    def reboot_target(target_alias: str) -> bool:
        return (
            _reboot_host(target_alias, hosts[target_alias])
            if hosts is not None
            else _reboot_host(target_alias)
        )

    failures = []
    if parallel:
        with ThreadPoolExecutor(max_workers=len(target_aliases)) as executor:
            future_to_alias = {
                executor.submit(reboot_target, alias): alias for alias in target_aliases
            }
            for future in as_completed(future_to_alias):
                if not future.result():
                    failures.append(future_to_alias[future])
    else:
        failures = [alias for alias in target_aliases if not reboot_target(alias)]
    if failures:
        failures.sort(key=target_aliases.index)
        _log_error(f"Reboot failed on {len(failures)} host(s): {', '.join(failures)}")
        sys.exit(1)
    _log_status_info(success_message)


def _reboot_host(alias: str, host: DeployHost | None = None) -> bool:
    """Reboot one target host and wait for it to come back."""
    host = host or _get_deploy_host(alias)
    try:
        host.run("sudo reboot &")
    except subprocess.CalledProcessError as err:
        _log_error(f"[{alias}] reboot: command failed: {err}")
        return False

    _log_status_info(f"[{alias}] reboot: waiting for {host.host} to shut down")
    port = host.port or 22
    if not _wait_for_port(
        host.host,
        port,
        shutdown=True,
        timeout=REBOOT_SHUTDOWN_TIMEOUT_SEC,
    ):
        _log_error(
            f"[{alias}] reboot: {host.host}:{port} did not shut down "
            f"within {REBOOT_SHUTDOWN_TIMEOUT_SEC}s"
        )
        return False

    _log_status_info(f"[{alias}] reboot: waiting for {host.host} to start")
    if not _wait_for_port(host.host, port, timeout=REBOOT_START_TIMEOUT_SEC):
        _log_error(
            f"[{alias}] reboot: {host.host}:{port} did not start "
            f"within {REBOOT_START_TIMEOUT_SEC}s"
        )
        return False
    _log_status_info(f"[{alias}] reboot: host is back up")
    return True


@task
def print_revision(_c: Context, alias: str = "") -> None:
    """
    Print the currently deployed git revision on the 'alias' host.
    If 'alias' is not specified, prints deployed revisions on all TARGETS.

    Example usage:
    inv print-revision
    inv print-revision --alias=hetzci-release
    """
    targets = OrderedDict([(alias, TARGETS.get(alias))]) if alias else TARGETS.all()
    deployed_revisions = _read_deployed_revisions(targets)

    git_info = _git_revision_info(
        rev
        for _, rev, _ in deployed_revisions
        if rev != "(unknown)" and "-dirty" not in rev
    )
    table_rows = []

    for target_alias, rev, reboot_needed in deployed_revisions:
        table_rows.append(
            [
                target_alias,
                targets[target_alias].hostname,
                reboot_needed,
                _format_revision_link(rev),
                git_info.get(rev, ["", "", ""])[1],
                git_info.get(rev, ["", "", ""])[2],
            ]
        )

    table_rows.sort(reverse=True, key=lambda row: row[4])  # sort by git_date
    _print_output(
        "\nCurrently deployed revision(s):\n\n"
        + tabulate(
            table_rows,
            headers=[
                "alias",
                "host address",
                "needs reboot",
                "revision (rev)",
                "rev date",
                "rev subject",
            ],
            tablefmt="fancy_outline",
        )
    )


################################################################################
# Initialization
################################################################################


def init() -> None:
    """Module initialization."""
    logger.remove()
    logger.add(
        _stderr_loguru_sink,
        level="INFO",
        format=LOGURU_COLOR_FORMAT,
        colorize=_stderr_supports_color(),
        filter=lambda record: not record["extra"].get("thread_local_stream", False),
    )
    logger.add(
        _thread_loguru_sink,
        level="INFO",
        format=LOGURU_FORMAT,
        colorize=False,
        filter=lambda record: record["extra"].get("thread_local_stream", False),
    )

    global ROOT, TARGETS  # pylint: disable=global-statement
    ROOT = Path(__file__).parent.resolve()
    os.chdir(ROOT)
    TARGETS = Targets()


init()
