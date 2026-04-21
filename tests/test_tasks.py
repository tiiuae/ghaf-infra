# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# pylint: disable=missing-function-docstring, protected-access, too-few-public-methods, wrong-import-position

"""Tests for extracted helper logic in tasks.py."""

import io
import logging
import re
import shlex
import subprocess
import sys
from collections import OrderedDict
from collections.abc import Callable
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import tasks


ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")


def _strip_ansi(text: str) -> str:
    """Remove ANSI color codes from text."""
    return ANSI_ESCAPE_RE.sub("", text)


def _assert_loguru_line(line: str, level: str, message: str) -> None:
    """Assert that one line matches the configured loguru output format."""
    padded_level = f"{level:<8}"
    pattern = (
        r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| "
        f"{re.escape(padded_level)}"
        r" \| "
        f"{re.escape(message)}"
    )
    assert re.fullmatch(pattern, line)


def test_confirm_respects_yes_without_prompt(monkeypatch: pytest.MonkeyPatch) -> None:
    """`yes=True` should bypass interactive prompting."""

    def fail_input(_prompt: str) -> str:
        raise AssertionError("input() should not be called when yes=True")

    monkeypatch.setattr("builtins.input", fail_input)
    assert tasks._confirm("Still continue? [y/N] ", yes=True)


def test_remote_stdout_omits_timeout_when_unspecified() -> None:
    """_remote_stdout should let DeployHost use its own infinite timeout."""
    calls: list[dict[str, object]] = []

    class FakeHost:
        """DeployHost-like stub that records keyword arguments."""

        def run(self, **kwargs: object) -> SimpleNamespace:
            """Record the forwarded arguments and return fake stdout."""
            calls.append(kwargs)
            return SimpleNamespace(stdout="demo-user\n")

    assert tasks._remote_stdout(FakeHost(), "whoami") == "demo-user"
    assert calls == [
        {
            "cmd": "whoami",
            "stdout": subprocess.PIPE,
            "stderr": None,
            "become_root": False,
        }
    ]


def test_remote_stdout_passes_requested_timeout_and_stderr_pipe() -> None:
    """Optional timeout and stderr capture should still be forwarded."""
    calls: list[dict[str, object]] = []

    class FakeHost:
        """DeployHost-like stub that records keyword arguments."""

        def run(self, **kwargs: object) -> SimpleNamespace:
            """Record the forwarded arguments and return fake stdout."""
            calls.append(kwargs)
            return SimpleNamespace(stdout="abc123\n")

    assert (
        tasks._remote_stdout(
            FakeHost(),
            "nixos-version --configuration-revision",
            timeout=5,
            suppress_stderr=True,
        )
        == "abc123"
    )
    assert calls == [
        {
            "cmd": "nixos-version --configuration-revision",
            "stdout": subprocess.PIPE,
            "stderr": subprocess.PIPE,
            "become_root": False,
            "timeout": 5,
        }
    ]


def test_assert_stateversion_exits_when_confirmation_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Version mismatch should exit when the operator declines confirmation."""

    def fake_confirm(_prompt: str, yes: bool) -> bool:
        return yes

    def fake_run(*args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args[0],
            0,
            stdout='{"stateVersion": "24.05", "nixpkgsVersion": "24.11"}',
            stderr="",
        )

    monkeypatch.setattr(
        tasks,
        "TARGETS",
        SimpleNamespace(get=lambda _alias: SimpleNamespace(nixosconfig="demo-host")),
    )
    monkeypatch.setattr(tasks, "ROOT", Path("/tmp/ghaf-infra"))
    monkeypatch.setattr(tasks, "_confirm", fake_confirm)
    monkeypatch.setattr(tasks.subprocess, "run", fake_run)

    with pytest.raises(SystemExit):
        tasks._assert_stateversion("demo", yes=False)


def test_generate_signed_user_key_runs_expected_commands(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Release key generation should run ssh-keygen and signing in sequence."""
    calls: list[list[str]] = []

    def fake_run_checked(
        cmd: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    ca = tmp_path / "ca/ssh_user_ca"
    monkeypatch.setattr(tasks, "_run_checked", fake_run_checked)

    key = tasks._generate_signed_user_key(ca, tmp_path, "builder-user")
    assert key == tmp_path / "controller/etc/ssh/certs/builder-user"
    assert calls == [
        ["ssh-keygen", "-f", str(key), "-C", "", "-N", ""],
        ["ssh-keygen", "-s", str(ca), "-I", "", "-n", "builder-user", f"{key}.pub"],
    ]


def test_announce_install_log_path_reports_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Install logging should announce the detailed log file path."""
    outputs: list[str] = []
    log_path = tmp_path / "logs/demo.log"

    def fake_log_info(message: str) -> None:
        outputs.append(message)

    monkeypatch.setattr(tasks.logger, "info", fake_log_info)

    tasks._announce_install_log_path("demo", log_path)

    assert outputs == [f"Writing install log for 'demo' to {log_path}"]


def test_context_stream_logger_routes_thread_local_output(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Context-aware handlers should prefer the thread-local stream."""
    logger_name = "tasks.test-context-stream"
    logger = logging.getLogger(logger_name)
    logger.handlers = []
    logger.propagate = False
    logger.setLevel(logging.INFO)

    logger.addHandler(logging.StreamHandler(io.StringIO()))

    tasks._configure_context_stream_logger(logger)

    logger.info("outside")
    outside_lines = capsys.readouterr().err.splitlines()
    assert len(outside_lines) == 1
    _assert_loguru_line(_strip_ansi(outside_lines[0]), "INFO", "outside")

    thread_stream = io.StringIO()
    token = tasks.THREAD_LOG_STREAM.set(thread_stream)
    try:
        logger.info("inside")
    finally:
        tasks.THREAD_LOG_STREAM.reset(token)

    assert capsys.readouterr().err == ""
    thread_lines = thread_stream.getvalue().splitlines()
    assert len(thread_lines) == 1
    assert "\x1b[" not in thread_lines[0]
    _assert_loguru_line(thread_lines[0], "INFO", "inside")


def test_context_stream_logger_preserves_command_prefix(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Bridged stdlib log records should keep deploykit-style host prefixes."""
    logger_name = "tasks.test-command-prefix"
    logger = logging.getLogger(logger_name)
    logger.handlers = []
    logger.propagate = False
    logger.setLevel(logging.INFO)

    logger.addHandler(logging.StreamHandler(io.StringIO()))

    tasks._configure_context_stream_logger(logger)

    logger.info("$ ssh example", extra={"command_prefix": "demo-host"})

    outside_lines = capsys.readouterr().err.splitlines()
    assert len(outside_lines) == 1
    _assert_loguru_line(
        _strip_ansi(outside_lines[0]), "INFO", "[demo-host] $ ssh example"
    )


def test_init_disables_stderr_color_when_stream_is_not_a_tty(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Non-interactive stderr output should stay free of ANSI escape codes."""

    class FakeStderr(io.StringIO):
        """String buffer that behaves like a redirected stderr stream."""

        def isatty(self) -> bool:
            return False

    stderr = FakeStderr()
    monkeypatch.setattr(tasks.sys, "stderr", stderr)
    monkeypatch.setattr(tasks.os, "chdir", lambda _path: None)

    tasks.init()
    tasks._log_info("outside")

    lines = stderr.getvalue().splitlines()
    assert len(lines) == 1
    assert "\x1b[" not in lines[0]
    _assert_loguru_line(lines[0], "INFO", "outside")


def test_log_status_info_logs_once_without_thread_local_context(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Status logs should not be duplicated during normal execution."""
    outputs: list[str] = []

    def fake_log_info(message: str) -> None:
        outputs.append(message)

    monkeypatch.setattr(tasks.logger, "info", fake_log_info)

    tasks._log_status_info("outside")

    assert outputs == ["outside"]


def test_log_status_info_mirrors_thread_local_output_to_console(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Status logs should go to both the host log file and the console mirror."""
    outputs: list[str] = []
    message = "[demo] install: building target system locally"

    def fake_log_info(log_message: str) -> None:
        outputs.append(log_message)

    monkeypatch.setattr(tasks.logger, "info", fake_log_info)

    log_path = tmp_path / "logs/demo.log"
    with tasks._thread_log_to_file(log_path):
        tasks._log_status_info(message)

    assert outputs == [message]
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    _assert_loguru_line(lines[0], "INFO", message)


def test_warn_and_confirm_mirrors_thread_local_warning_to_console(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path: Path,
) -> None:
    """Prompt-triggering warnings should stay visible during logged installs."""

    def fake_input(prompt: str) -> str:
        print(prompt, end="")
        return "n"

    monkeypatch.setattr("builtins.input", fake_input)

    log_path = tmp_path / "logs/demo.log"
    with pytest.raises(SystemExit):
        with tasks._thread_log_to_file(log_path):
            tasks._warn_and_confirm("dynamic IP warning", yes=False)

    captured = capsys.readouterr()
    assert captured.out == "Still continue? [y/N] "
    err_lines = captured.err.splitlines()
    assert len(err_lines) == 1
    _assert_loguru_line(_strip_ansi(err_lines[0]), "WARNING", "dynamic IP warning")

    file_lines = log_path.read_text(encoding="utf-8").splitlines()
    assert len(file_lines) == 1
    _assert_loguru_line(file_lines[0], "WARNING", "dynamic IP warning")


def test_install_creates_detailed_log_and_runs_inner_install(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Single-host installs should always wrap the inner workflow in a log file."""
    outputs: list[str] = []
    clone_calls: list[tuple[object, str]] = []
    run_calls: list[tuple[object, str, str | None, bool, str | None]] = []
    log_dir = tmp_path / "install-logs"

    def fake_log_info(message: str) -> None:
        outputs.append(message)

    def fake_mkdtemp(*, prefix: str) -> str:
        assert prefix == "install-logs-"
        return str(log_dir)

    def fake_clone_context_for_stream(context: object, stream: object) -> str:
        clone_calls.append((context, stream.name))
        return "logged-context"

    def fake_run_install(
        context: object,
        alias: str,
        *,
        user: str | None = None,
        yes: bool = False,
        copy_dir: str | None = None,
    ) -> None:
        run_calls.append((context, alias, user, yes, copy_dir))

    monkeypatch.setattr(tasks.logger, "info", fake_log_info)
    monkeypatch.setattr(tasks, "mkdtemp", fake_mkdtemp)
    monkeypatch.setattr(
        tasks, "_clone_context_for_stream", fake_clone_context_for_stream
    )
    monkeypatch.setattr(tasks, "_run_install", fake_run_install)

    root_context = object()
    tasks.install.body(
        root_context,
        "demo",
        user="operator",
        yes=True,
        copy_dir="/tmp/copied",
    )

    log_path = log_dir / "demo.log"
    assert outputs == [f"Writing install log for 'demo' to {log_path}"]
    assert clone_calls == [(root_context, str(log_path))]
    assert run_calls == [("logged-context", "demo", "operator", True, "/tmp/copied")]
    assert log_path.exists()


def test_install_reports_failure_with_log_path(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Single-host install failures should keep the traceback and print the log path."""
    errors: list[str] = []
    log_dir = tmp_path / "install-logs"

    def fake_mkdtemp(*, prefix: str) -> str:
        assert prefix == "install-logs-"
        return str(log_dir)

    def same_context(context: object, _stream: object) -> object:
        return context

    def fail_run_install(
        _context: object,
        _alias: str,
        *,
        user: str | None = None,
        yes: bool = False,
        copy_dir: str | None = None,
    ) -> None:
        raise subprocess.CalledProcessError(2, "nixos-anywhere")

    def fake_log_error(message: str) -> None:
        errors.append(message)

    monkeypatch.setattr(tasks, "mkdtemp", fake_mkdtemp)
    monkeypatch.setattr(tasks, "_clone_context_for_stream", same_context)
    monkeypatch.setattr(tasks, "_run_install", fail_run_install)
    monkeypatch.setattr(tasks.logger, "error", fake_log_error)

    log_path = log_dir / "demo.log"
    with pytest.raises(subprocess.CalledProcessError):
        tasks.install.body(object(), "demo", yes=True)

    assert len(errors) == 2
    assert errors[0].startswith("Install failed for 'demo': CalledProcessError:")
    assert errors[1] == f"See detailed install log: {log_path}"


def test_install_release_hosts_parallelizes_all_release_hosts(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """All release hosts should be dispatched through the parallel install phase."""
    expected_jobs = [
        ("hetz86-rel-2", str(tmp_path / "builder")),
        ("hetzarm-rel-1", str(tmp_path / "builder")),
        ("hetzci-release", str(tmp_path / "controller")),
    ]
    submitted: list[tuple[object, str, str]] = []
    install_calls: list[tuple[object, str, bool, str | None]] = []
    clone_calls: list[object] = []
    prepare_calls: list[str] = []
    call_order: list[tuple[str, str]] = []

    class FakeFuture:
        """Minimal future stub that runs the task when awaited."""

        def __init__(self, callback: Callable[[], None]) -> None:
            self._callback = callback

        def result(self) -> None:
            self._callback()

    class FakeExecutor:
        """Minimal executor stub for deterministic release-install tests."""

        def __init__(self, *, max_workers: int) -> None:
            assert max_workers == len(expected_jobs)

        def __enter__(self) -> "FakeExecutor":
            return self

        def __exit__(self, *_args: object) -> None:
            pass

        def submit(
            self, func: Callable[..., None], *args: object, **kwargs: object
        ) -> FakeFuture:
            submitted.append((args[0], args[1], kwargs["copy_dir"]))
            return FakeFuture(lambda: func(*args, **kwargs))

    def fake_clone_context(context: object) -> str:
        clone_calls.append(context)
        return f"host-context-{len(clone_calls)}"

    def fake_resolve_secrets(alias: str) -> object:
        prepare_calls.append(alias)
        call_order.append(("resolve", alias))
        return object()

    def fake_install(
        context: object,
        alias: str,
        *,
        yes: bool,
        copy_dir: str | None = None,
    ) -> None:
        install_calls.append((context, alias, yes, copy_dir))
        call_order.append(("install", alias))

    monkeypatch.setattr(tasks, "ThreadPoolExecutor", FakeExecutor)
    monkeypatch.setattr(
        tasks, "as_completed", lambda submitted_futures: submitted_futures
    )
    monkeypatch.setattr(
        tasks, "TARGETS", SimpleNamespace(resolve_secrets=fake_resolve_secrets)
    )
    monkeypatch.setattr(tasks, "_clone_context", fake_clone_context)
    monkeypatch.setattr(tasks, "install", fake_install)

    root_context = object()
    tasks._install_release_hosts(root_context, tmp_path)

    assert prepare_calls == [alias for alias, _copy_dir in expected_jobs]
    assert submitted == [
        ("host-context-1", "hetz86-rel-2", str(tmp_path / "builder")),
        ("host-context-2", "hetzarm-rel-1", str(tmp_path / "builder")),
        ("host-context-3", "hetzci-release", str(tmp_path / "controller")),
    ]
    assert clone_calls == [root_context, root_context, root_context]
    assert install_calls == [
        (
            "host-context-1",
            "hetz86-rel-2",
            True,
            str(tmp_path / "builder"),
        ),
        (
            "host-context-2",
            "hetzarm-rel-1",
            True,
            str(tmp_path / "builder"),
        ),
        (
            "host-context-3",
            "hetzci-release",
            True,
            str(tmp_path / "controller"),
        ),
    ]
    assert call_order[:3] == [
        ("resolve", "hetz86-rel-2"),
        ("resolve", "hetzarm-rel-1"),
        ("resolve", "hetzci-release"),
    ]


def test_install_release_hosts_reports_all_parallel_failures(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Parallel release install should log every failing host before exiting."""
    errors: list[str] = []

    class FakeFuture:
        """Minimal future stub that runs the task when awaited."""

        def __init__(self, callback: Callable[[], None]) -> None:
            self._callback = callback

        def result(self) -> None:
            self._callback()

    class FakeExecutor:
        """Minimal executor stub for failure aggregation tests."""

        def __init__(self, *, max_workers: int) -> None:
            assert max_workers == 3

        def __enter__(self) -> "FakeExecutor":
            return self

        def __exit__(self, *_args: object) -> None:
            pass

        def submit(
            self, func: Callable[..., None], *args: object, **kwargs: object
        ) -> FakeFuture:
            return FakeFuture(lambda: func(*args, **kwargs))

    def fake_install(
        _context: object,
        alias: str,
        *,
        yes: bool,
        copy_dir: str | None = None,
    ) -> None:
        assert yes
        assert copy_dir is not None
        if alias == "hetz86-rel-2":
            raise SystemExit(1)
        if alias == "hetzci-release":
            raise subprocess.CalledProcessError(2, "nixos-anywhere")

    def identity_as_completed(submitted_futures: object) -> object:
        return submitted_futures

    def same_context(context: object) -> object:
        return context

    def fake_log_error(message: str) -> None:
        errors.append(message)

    monkeypatch.setattr(tasks, "ThreadPoolExecutor", FakeExecutor)
    monkeypatch.setattr(tasks, "as_completed", identity_as_completed)
    monkeypatch.setattr(
        tasks, "TARGETS", SimpleNamespace(resolve_secrets=lambda _alias: object())
    )
    monkeypatch.setattr(tasks, "_clone_context", same_context)
    monkeypatch.setattr(tasks, "install", fake_install)
    monkeypatch.setattr(tasks.logger, "error", fake_log_error)

    with pytest.raises(
        RuntimeError, match="2 host\\(s\\): hetz86-rel-2, hetzci-release"
    ):
        tasks._install_release_hosts(object(), tmp_path)

    assert any(
        "hetz86-rel-2" in message and "SystemExit: 1" in message for message in errors
    )
    assert any(
        "hetzci-release" in message and "CalledProcessError:" in message
        for message in errors
    )


def test_build_nixos_anywhere_command_is_shell_safe(tmp_path: Path) -> None:
    """The assembled invoke command should round-trip through shlex safely."""
    target = tasks.TargetHost(hostname="host", nixosconfig="demo-config")
    command = tasks._build_nixos_anywhere_command(
        "root@example",
        str(tmp_path / "tmp dir"),
        target,
        kexec_url="https://example.test/image.tar.gz",
    )

    assert shlex.split(command) == [
        "nixos-anywhere",
        "root@example",
        "--extra-files",
        str(tmp_path / "tmp dir"),
        "--kexec",
        "https://example.test/image.tar.gz",
        "--flake",
        ".#demo-config",
        "--option",
        "accept-flake-config",
        "true",
    ]


def test_connect_release_testagent_retries_until_success(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Connection helper should retry locally before succeeding."""
    attempts = {"count": 0}
    sleeps: list[int] = []

    class FakeHost:
        """DeployHost-like stub used for retry logic tests."""

        def run(self, *, cmd: str, timeout: int) -> SimpleNamespace:
            """Simulate a flaky remote `connect` command."""
            assert cmd == shlex.join(["connect", tasks.RELEASE_TESTAGENT_URL])
            assert timeout == 20
            attempts["count"] += 1
            if attempts["count"] < 3:
                raise subprocess.CalledProcessError(1, cmd)
            return SimpleNamespace(stdout="")

    def fake_sleep(seconds: int) -> None:
        sleeps.append(seconds)

    monkeypatch.setattr(tasks.time, "sleep", fake_sleep)

    assert tasks._connect_release_testagent(FakeHost()) is True
    assert attempts["count"] == 3
    assert sleeps == [
        tasks.RELEASE_CONNECT_SLEEP_SEC,
        tasks.RELEASE_CONNECT_SLEEP_SEC,
    ]


def test_deploy_release_testagent_skips_unreachable_host(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Release testagent deploy should fail fast when SSH is unreachable."""
    infos: list[str] = []
    probes: list[tuple[str, int, int | float]] = []

    class FakeContext:
        """Invoke-like context stub that must not run deploy on probe failure."""

        def run(self, _command: str, *, warn: bool) -> SimpleNamespace:
            raise AssertionError("deploy should not run when the SSH probe fails")

    def fake_can_connect(host: str, port: int, timeout: int | float = 1) -> bool:
        probes.append((host, port, timeout))
        return False

    def fake_log_info(message: str) -> None:
        infos.append(message)

    monkeypatch.setattr(tasks, "_can_connect", fake_can_connect)
    monkeypatch.setattr(tasks.logger, "info", fake_log_info)

    host = SimpleNamespace(host="172.18.16.32", port=None)

    assert tasks._deploy_release_testagent(FakeContext(), host) is False
    assert probes == [("172.18.16.32", 22, tasks.RELEASE_DEPLOY_SSH_PROBE_TIMEOUT_SEC)]
    assert infos[0] == (
        "Failed deploying 'testagent-release'. "
        "The release environment is otherwise up, but you should manually deploy "
        "the testagent-release, then connect it to the release Jenkins instance. "
        "Hint: could not reach '172.18.16.32:22' over TCP within "
        f"{tasks.RELEASE_DEPLOY_SSH_PROBE_TIMEOUT_SEC}s. "
        "Perhaps you need to connect a VPN?"
    )
    assert len(infos) == 1


def test_decrypt_host_key_respects_yes_on_sops_failure(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """sops failure with yes=True should not block on an interactive prompt."""

    def fail_sops(
        cmd: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        if cmd[:2] == ["sops", "--extract"]:
            raise subprocess.CalledProcessError(1, cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    def fail_input(_prompt: str) -> str:
        raise AssertionError("input() must not be called when yes=True")

    monkeypatch.setattr(tasks, "_run_checked", fail_sops)
    monkeypatch.setattr("builtins.input", fail_input)

    target = tasks.TargetHost(
        hostname="h",
        nixosconfig="demo",
        secretspath=str(tmp_path / "secrets.yaml"),
    )
    tasks._decrypt_host_key(target, str(tmp_path / "out"), yes=True)


def test_warn_and_confirm_exits_when_declined(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """_warn_and_confirm should exit when the user declines."""
    monkeypatch.setattr(tasks, "_confirm", lambda _prompt, yes: yes)
    with pytest.raises(SystemExit):
        tasks._warn_and_confirm("scary warning", yes=False)


def test_run_json_exits_on_subprocess_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """_run_json should exit cleanly when the underlying command fails."""

    def fail_run(cmd: list[str], **_kwargs: object) -> subprocess.CompletedProcess[str]:
        raise subprocess.CalledProcessError(1, cmd, output="", stderr="nix error")

    monkeypatch.setattr(tasks, "_run_checked", fail_run)
    with pytest.raises(SystemExit):
        tasks._run_json(["nix", "eval", "--json", "."])


def test_git_revision_info_parses_log_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """_git_revision_info parses the delimited git log output by hash."""
    delim = tasks.REVISION_DELIM
    stdout = (
        f"abc123{delim}2026-01-01{delim}initial commit\n"
        f"def456{delim}2026-01-02{delim}fix bug\n"
    )

    def fake_run_checked(
        cmd: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(cmd, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(tasks, "_run_checked", fake_run_checked)

    assert tasks._git_revision_info() == {
        "abc123": ["abc123", "2026-01-01", "initial commit"],
        "def456": ["def456", "2026-01-02", "fix bug"],
    }


def test_git_revision_info_limits_lookup_to_selected_hashes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Filtered lookup should avoid traversing the full git history."""
    calls: list[list[str]] = []
    delim = tasks.REVISION_DELIM

    def fake_run_checked(
        cmd: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        calls.append(cmd)
        return subprocess.CompletedProcess(
            cmd,
            0,
            stdout=f"abc123{delim}2026-01-01{delim}initial commit\n",
            stderr="",
        )

    monkeypatch.setattr(tasks, "_run_checked", fake_run_checked)

    assert tasks._git_revision_info(["abc123", "abc123"]) == {
        "abc123": ["abc123", "2026-01-01", "initial commit"],
    }
    assert calls == [
        [
            "git",
            "log",
            "--no-walk",
            "--ignore-missing",
            f"--pretty=format:%H{delim}%cs{delim}%s",
            "abc123",
        ]
    ]


def test_print_revision_collects_remote_hosts_before_git_lookup(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """print_revision should only ask git for clean deployed revisions."""

    class FakeExecutor:
        """Minimal executor stub for deterministic tests."""

        def __init__(self, *, max_workers: int) -> None:
            self.max_workers = max_workers

        def __enter__(self) -> "FakeExecutor":
            return self

        def __exit__(self, *_args: object) -> None:
            return None

        def map(self, func: object, aliases: list[str]) -> list[tuple[str, str]]:
            """Apply the submitted function in-order for deterministic tests."""
            assert self.max_workers == len(aliases)
            assert func is tasks._read_deployed_revision
            return [func(alias) for alias in aliases]

    revisions = {
        "alpha": "abc123",
        "beta": "abc123",
        "gamma": "dirtyrev-dirty",
        "delta": "(unknown)",
    }

    monkeypatch.setattr(
        tasks,
        "TARGETS",
        SimpleNamespace(
            all=lambda: OrderedDict((alias, object()) for alias in revisions)
        ),
    )
    monkeypatch.setattr(
        tasks,
        "_read_deployed_revision",
        lambda alias: (alias, revisions[alias]),
    )
    monkeypatch.setattr(
        tasks,
        "_git_revision_info",
        lambda selected: {"abc123": ["abc123", "2026-01-01", "initial commit"]}
        if list(selected) == ["abc123", "abc123"]
        else {},
    )
    monkeypatch.setattr(tasks, "ThreadPoolExecutor", FakeExecutor)

    tasks.print_revision.body(None, alias="")

    output = capsys.readouterr().out
    assert "alpha" in output
    assert "beta" in output
    assert "gamma" in output
    assert "delta" in output
    assert "2026-01-01" in output
    assert "initial commit" in output


def test_targets_get_exits_on_unknown_alias(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Targets.get should exit cleanly when the alias is not in nix output."""

    def fake_run_json(_cmd: list[str]) -> dict:
        return {"demo": {"hostname": "h", "config": "demo-config", "secrets": None}}

    monkeypatch.setattr(tasks, "_run_json", fake_run_json)
    monkeypatch.setattr(tasks, "ROOT", Path("/tmp/ghaf-infra"))

    targets = tasks.Targets()
    with pytest.raises(SystemExit):
        targets.get("missing")
