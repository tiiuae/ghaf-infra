# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# pylint: disable=protected-access, too-few-public-methods, wrong-import-position

"""Tests for extracted helper logic in tasks.py."""

import shlex
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import tasks


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
