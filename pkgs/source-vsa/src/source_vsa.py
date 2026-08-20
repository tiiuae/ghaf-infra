#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""Issue, fetch, inspect, and verify SLSA Source VSA bundles."""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


PREDICATE_TYPE = "https://slsa.dev/verification_summary/v1"
STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
OIDC_ISSUER = "https://token.actions.githubusercontent.com"
BUNDLE_FILENAME = "source-vsa.sigstore.json"
BUNDLE_MEDIA_TYPE = "application/vnd.dev.sigstore.bundle.v0.3+json"
REGISTRY_HOST = "ghcr.io"
REGISTRY_ARTIFACT = "source-vsa"
SLSA_VERSION = "1.2"
SUPPORTED_LEVEL = "SLSA_SOURCE_LEVEL_1"
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")


class SourceVSAError(Exception):
    """An expected source VSA operation failed."""


def ref_allowed(ref: str, allowed_refs: list[str]) -> bool:
    """Return whether a concrete source ref matches an allowed policy pattern."""
    return any(re.fullmatch(pattern, ref) for pattern in allowed_refs)


def run_command(
    arguments: list[str],
    *,
    input_text: str | None = None,
    check: bool = True,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run an external command and retain its output for useful failures."""
    result = subprocess.run(
        arguments,
        check=False,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise SourceVSAError(f"{' '.join(arguments[:2])} failed: {detail}")
    return result


def load_policy(
    path: Path, *, workspace: Path | None = None
) -> tuple[dict[str, Any], str, str | None]:
    """Load the policy and return it with the digest of its exact bytes."""
    try:
        contents = path.read_bytes()
        policy = yaml.safe_load(contents)
    except (OSError, yaml.YAMLError) as error:
        raise SourceVSAError(f"cannot read policy {path}: {error}") from error

    if not isinstance(policy, dict):
        raise SourceVSAError(f"policy {path} is not a mapping")
    policy_path = None
    if workspace is not None:
        try:
            policy_path = path.resolve().relative_to(workspace.resolve())
        except ValueError as error:
            raise SourceVSAError("policy must be inside GITHUB_WORKSPACE") from error
    return (
        policy,
        hashlib.sha256(contents).hexdigest(),
        policy_path.as_posix() if policy_path is not None else None,
    )


def policy_context(
    policy_source: tuple[dict[str, Any], str, str | None],
    repository: str,
    commit: str,
    action_sha: str | None = None,
    *,
    verified_level: str,
) -> dict[str, Any]:
    """Validate inputs and derive all policy-controlled names."""
    policy, policy_digest, policy_path = policy_source
    repository = repository.lower()
    if not COMMIT_PATTERN.fullmatch(commit) or commit == "0" * 40:
        raise SourceVSAError(f"invalid Git commit: {commit}")
    if action_sha is not None and (
        not COMMIT_PATTERN.fullmatch(action_sha) or action_sha == "0" * 40
    ):
        raise SourceVSAError(f"invalid issuer action commit: {action_sha}")
    if verified_level != SUPPORTED_LEVEL:
        raise SourceVSAError(f"unsupported verified level: {verified_level}")

    allowed_refs = policy.get("refs")
    if (
        not isinstance(allowed_refs, list)
        or not allowed_refs
        or not all(isinstance(item, str) for item in allowed_refs)
    ):
        raise SourceVSAError("policy has no valid refs")
    try:
        for pattern in allowed_refs:
            re.compile(pattern)
    except re.error as error:
        raise SourceVSAError(f"policy has an invalid ref pattern: {error}") from error
    verifier = policy.get("verifier")
    if not isinstance(verifier, dict):
        raise SourceVSAError("policy verifier configuration is missing")
    required_strings = {
        "verifier.id": verifier.get("id"),
        "workflowPath": policy.get("workflowPath"),
    }
    if not all(isinstance(value, str) and value for value in required_strings.values()):
        raise SourceVSAError("policy verifier or workflow configuration is invalid")

    context = {
        "repository": repository,
        "commit": commit,
        "allowed_refs": allowed_refs,
        "verified_level": verified_level,
        "verifier_id": verifier["id"],
        "workflow": f"{repository}/{policy['workflowPath'].lstrip('/')}",
        "policy_digest": policy_digest,
        "reference": f"{REGISTRY_HOST}/{repository}/{REGISTRY_ARTIFACT}:{commit}",
        "registry_host": REGISTRY_HOST,
    }
    if action_sha is not None:
        context["action_sha"] = action_sha
        if policy_path is not None:
            context["policy_uri"] = (
                f"https://github.com/{repository}/blob/{commit}/{policy_path}"
            )
    return context


def create_statement(context: dict[str, Any], ref: str) -> dict[str, Any]:
    """Create the canonical Source VSA statement."""
    repository = context["repository"]
    commit = context["commit"]
    return {
        "_type": STATEMENT_TYPE,
        "subject": [
            {
                "uri": f"https://github.com/{repository}/commit/{commit}",
                "digest": {"gitCommit": commit},
                "annotations": {"sourceRefs": [ref]},
            }
        ],
        "predicateType": PREDICATE_TYPE,
        "predicate": {
            "verifier": {
                "id": context["verifier_id"],
                "version": {"action": context["action_sha"]},
            },
            "timeVerified": datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
            "resourceUri": f"git+https://github.com/{repository}",
            "policy": {
                "uri": context["policy_uri"],
                "digest": {"sha256": context["policy_digest"]},
            },
            "verificationResult": "PASSED",
            "verifiedLevels": [context["verified_level"]],
            "slsaVersion": SLSA_VERSION,
        },
    }


def statement_from_bundle(bundle_path: Path) -> dict[str, Any]:
    """Extract the DSSE payload statement from a Sigstore bundle."""
    try:
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        encoded_payload = bundle["dsseEnvelope"]["payload"]
        statement = json.loads(base64.b64decode(encoded_payload, validate=True))
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise SourceVSAError(
            f"invalid Sigstore bundle {bundle_path}: {error}"
        ) from error
    if not isinstance(statement, dict):
        raise SourceVSAError(f"bundle payload is not a statement: {bundle_path}")
    return statement


def action_sha_from_bundle(bundle_path: Path) -> str:
    """Read the exact composite-action version claimed by a VSA bundle."""
    statement = statement_from_bundle(bundle_path)
    try:
        action_sha = statement["predicate"]["verifier"]["version"]["action"]
    except (KeyError, TypeError) as error:
        raise SourceVSAError("VSA issuer action version is missing") from error
    if not isinstance(action_sha, str):
        raise SourceVSAError("VSA issuer action version is invalid")
    return action_sha


def verify_statement(statement: dict[str, Any], context: dict[str, Any]) -> None:
    """Require the exact statement shape and policy decisions used by this issuer."""
    expected_subject = {
        "uri": (
            f"https://github.com/{context['repository']}/commit/{context['commit']}"
        ),
        "digest": {"gitCommit": context["commit"]},
    }
    subjects = statement.get("subject")
    if not isinstance(subjects, list) or len(subjects) != 1:
        raise SourceVSAError("VSA must contain exactly one subject")
    subject = subjects[0]
    if not isinstance(subject, dict) or any(
        subject.get(key) != value for key, value in expected_subject.items()
    ):
        raise SourceVSAError("VSA subject does not match the requested source commit")
    annotations = subject.get("annotations")
    source_refs = (
        annotations.get("sourceRefs") if isinstance(annotations, dict) else None
    )
    if (
        not isinstance(source_refs, list)
        or not source_refs
        or not all(
            isinstance(ref, str) and ref_allowed(ref, context["allowed_refs"])
            for ref in source_refs
        )
    ):
        raise SourceVSAError("VSA sourceRefs are not allowed by policy")

    expected_predicate = {
        "verifier": {
            "id": context["verifier_id"],
            "version": {"action": context["action_sha"]},
        },
        "resourceUri": f"git+https://github.com/{context['repository']}",
        "verificationResult": "PASSED",
        "verifiedLevels": [context["verified_level"]],
        "slsaVersion": SLSA_VERSION,
    }
    predicate = statement.get("predicate")
    if statement.get("_type") != STATEMENT_TYPE:
        raise SourceVSAError("unexpected in-toto statement type")
    if statement.get("predicateType") != PREDICATE_TYPE:
        raise SourceVSAError("unexpected VSA predicate type")
    if not isinstance(predicate, dict) or any(
        predicate.get(key) != value for key, value in expected_predicate.items()
    ):
        raise SourceVSAError("VSA predicate does not match the issuer policy")
    statement_policy = predicate.get("policy")
    expected_policy_uri_prefix = (
        f"https://github.com/{context['repository']}/blob/{context['commit']}/"
    )
    if not isinstance(statement_policy, dict) or statement_policy.get("digest") != {
        "sha256": context["policy_digest"]
    }:
        raise SourceVSAError("VSA policy does not match the issuer policy")
    statement_policy_uri = statement_policy.get("uri")
    if (
        not isinstance(statement_policy_uri, str)
        or not statement_policy_uri.startswith(expected_policy_uri_prefix)
        or statement_policy_uri == expected_policy_uri_prefix
    ):
        raise SourceVSAError("VSA policy URI does not match the source revision")
    if "policy_uri" in context and statement_policy_uri != context["policy_uri"]:
        raise SourceVSAError("VSA policy URI does not match the supplied policy path")
    time_verified = predicate.get("timeVerified")
    if not isinstance(time_verified, str):
        raise SourceVSAError("VSA timeVerified is missing")
    try:
        parsed_time = datetime.fromisoformat(time_verified.replace("Z", "+00:00"))
    except ValueError as error:
        raise SourceVSAError("VSA timeVerified is invalid") from error
    if parsed_time.tzinfo is None:
        raise SourceVSAError("VSA timeVerified must include a timezone")


def verify_bundle(bundle_path: Path, context: dict[str, Any]) -> None:
    """Verify the Sigstore identity, source claims, and VSA payload."""
    statement = statement_from_bundle(bundle_path)
    verify_statement(statement, context)
    source_ref = statement["subject"][0]["annotations"]["sourceRefs"][0]
    run_command(
        [
            "cosign",
            "verify-blob-attestation",
            "--bundle",
            str(bundle_path),
            "--digest",
            context["commit"],
            "--digestAlg",
            "gitCommit",
            "--type",
            PREDICATE_TYPE,
            "--certificate-identity",
            f"https://github.com/{context['workflow']}@{source_ref}",
            "--certificate-oidc-issuer",
            OIDC_ISSUER,
            "--certificate-github-workflow-repository",
            context["repository"],
            "--certificate-github-workflow-ref",
            source_ref,
            "--certificate-github-workflow-sha",
            context["commit"],
            "--certificate-github-workflow-trigger",
            "push",
        ]
    )


def pull_bundle(
    reference: str,
    destination: Path,
    *,
    registry_config: Path | None = None,
    allow_missing: bool = False,
) -> Path | None:
    """Pull a bundle and distinguish an absent tag from registry failures."""
    arguments = ["oras", "pull", "--output", str(destination)]
    if registry_config is not None:
        arguments.extend(["--registry-config", str(registry_config)])
    result = run_command([*arguments, reference], check=False)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        missing = any(
            marker in detail.lower()
            for marker in ("not found", "manifest unknown", "404")
        )
        if allow_missing and missing:
            return None
        raise SourceVSAError(f"oras pull failed for {reference}: {detail}")

    bundle_path = destination / BUNDLE_FILENAME
    if not bundle_path.is_file():
        raise SourceVSAError(f"OCI artifact does not contain {BUNDLE_FILENAME}")
    return bundle_path


def issue(args: argparse.Namespace) -> None:
    """Issue an immutable VSA, or validate the one already at its commit tag."""
    if args.event_name != "push":
        raise SourceVSAError(f"unsupported GitHub event: {args.event_name}")
    if args.event_path is None:
        raise SourceVSAError("GITHUB_EVENT_PATH is required to issue a VSA")
    try:
        event = json.loads(args.event_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SourceVSAError(f"cannot read GitHub event payload: {error}") from error
    if not isinstance(event, dict) or event.get("deleted") is not False:
        raise SourceVSAError("ref deletion events cannot issue a VSA")
    token = os.environ.get("GITHUB_TOKEN")
    actor = os.environ.get("GITHUB_ACTOR")
    if not token or not actor:
        raise SourceVSAError(
            "GITHUB_TOKEN and GITHUB_ACTOR are required to issue a VSA"
        )

    if not os.environ.get("GITHUB_WORKSPACE"):
        raise SourceVSAError("GITHUB_WORKSPACE is required to issue a VSA")

    context = policy_context(
        load_policy(args.policy, workspace=Path(os.environ["GITHUB_WORKSPACE"])),
        args.repository,
        args.commit,
        args.action_sha,
        verified_level=args.verified_level,
    )
    if not isinstance(args.ref, str) or not ref_allowed(
        args.ref, context["allowed_refs"]
    ):
        raise SourceVSAError(f"source ref is not allowed by policy: {args.ref}")
    with tempfile.TemporaryDirectory(prefix="source-vsa-") as temporary:
        workdir = Path(temporary)
        registry_config = workdir / "oras-config.json"
        run_command(
            [
                "oras",
                "login",
                "--username",
                actor,
                "--password-stdin",
                "--registry-config",
                str(registry_config),
                context["registry_host"],
            ],
            input_text=token,
        )

        authenticated = workdir / "authenticated"
        authenticated.mkdir()
        bundle = pull_bundle(
            context["reference"],
            authenticated,
            registry_config=registry_config,
            allow_missing=True,
        )
        if bundle is None:
            statement_path = workdir / "statement.json"
            bundle = workdir / BUNDLE_FILENAME
            statement_path.write_text(
                json.dumps(create_statement(context, args.ref), separators=(",", ":")),
                encoding="utf-8",
            )
            run_command(
                [
                    "cosign",
                    "attest-blob",
                    "--statement",
                    str(statement_path),
                    "--bundle",
                    str(bundle),
                    "--yes",
                ]
            )
            verify_bundle(bundle, context)
            run_command(
                [
                    "oras",
                    "push",
                    "--registry-config",
                    str(registry_config),
                    "--artifact-type",
                    BUNDLE_MEDIA_TYPE,
                    "--annotation",
                    f"org.opencontainers.image.source=https://github.com/{context['repository']}",
                    "--annotation",
                    f"dev.slsa.source.commit={context['commit']}",
                    context["reference"],
                    f"{BUNDLE_FILENAME}:{BUNDLE_MEDIA_TYPE}",
                ],
                cwd=workdir,
            )
        else:
            verify_bundle(bundle, context)

        public = workdir / "public"
        public.mkdir()
        anonymous_config = workdir / "anonymous-config.json"
        anonymous_config.write_text('{"auths":{}}', encoding="utf-8")
        try:
            public_bundle = pull_bundle(
                context["reference"], public, registry_config=anonymous_config
            )
        except SourceVSAError as error:
            raise SourceVSAError(
                f"anonymous verification failed: {error}. If this is the first "
                f"publication, make the {context['repository']}/{REGISTRY_ARTIFACT} "
                "package public in GitHub under Package settings > Danger Zone > "
                "Change visibility, then rerun this workflow"
            ) from error
        assert public_bundle is not None
        verify_bundle(public_bundle, context)
        if args.bundle is not None:
            shutil.copyfile(public_bundle, args.bundle)
        print(
            json.dumps(
                {
                    "reference": context["reference"],
                    "bundleSha256": hashlib.sha256(
                        public_bundle.read_bytes()
                    ).hexdigest(),
                }
            )
        )


def verify(args: argparse.Namespace) -> None:
    """Verify a local VSA bundle."""
    context = policy_context(
        load_policy(args.policy),
        args.repository,
        args.commit,
        action_sha_from_bundle(args.bundle),
        verified_level=args.verified_level,
    )
    verify_bundle(args.bundle, context)


def fetch(args: argparse.Namespace) -> None:
    """Fetch a public VSA bundle and verify it before returning it."""
    policy_source = load_policy(args.policy)
    lookup_context = policy_context(
        policy_source,
        args.repository,
        args.commit,
        verified_level=args.verified_level,
    )
    with tempfile.TemporaryDirectory(prefix="source-vsa-") as temporary:
        bundle = pull_bundle(lookup_context["reference"], Path(temporary))
        assert bundle is not None
        context = policy_context(
            policy_source,
            args.repository,
            args.commit,
            action_sha_from_bundle(bundle),
            verified_level=args.verified_level,
        )
        verify_bundle(bundle, context)
        shutil.copyfile(bundle, args.bundle)


def inspect_bundle(args: argparse.Namespace) -> None:
    """Print the unverified VSA statement embedded in a Sigstore bundle."""
    print(json.dumps(statement_from_bundle(args.bundle), indent=2))


def parser() -> argparse.ArgumentParser:
    """Build the command-line interface."""
    command_parser = argparse.ArgumentParser(description=__doc__)
    subparsers = command_parser.add_subparsers(dest="command", required=True)

    def common_arguments(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--policy", required=True, type=Path)
        subparser.add_argument(
            "--repository", default=os.environ.get("GITHUB_REPOSITORY"), required=False
        )
        subparser.add_argument(
            "--commit", default=os.environ.get("GITHUB_SHA"), required=False
        )
        subparser.add_argument("--verified-level", default=SUPPORTED_LEVEL)

    issue_parser = subparsers.add_parser("issue", help="issue or reuse a Source VSA")
    common_arguments(issue_parser)
    issue_parser.add_argument("--action-sha", required=True)
    issue_parser.add_argument("--ref", default=os.environ.get("GITHUB_REF"))
    issue_parser.add_argument(
        "--event-name", default=os.environ.get("GITHUB_EVENT_NAME")
    )
    issue_parser.add_argument(
        "--event-path", default=os.environ.get("GITHUB_EVENT_PATH"), type=Path
    )
    issue_parser.add_argument("--bundle", type=Path)
    issue_parser.set_defaults(function=issue)

    verify_parser = subparsers.add_parser("verify", help="verify a local Source VSA")
    common_arguments(verify_parser)
    verify_parser.add_argument("--bundle", required=True, type=Path)
    verify_parser.set_defaults(function=verify)

    fetch_parser = subparsers.add_parser("fetch", help="fetch and verify a Source VSA")
    common_arguments(fetch_parser)
    fetch_parser.add_argument("--bundle", required=True, type=Path)
    fetch_parser.set_defaults(function=fetch)

    inspect_parser = subparsers.add_parser(
        "inspect", help="print the unverified VSA statement from a bundle"
    )
    inspect_parser.add_argument("--bundle", required=True, type=Path)
    inspect_parser.set_defaults(function=inspect_bundle)
    return command_parser


def main() -> int:
    """Run the source-vsa command."""
    command_parser = parser()
    args = command_parser.parse_args()
    if args.command != "inspect" and (not args.repository or not args.commit):
        command_parser.error(
            "--repository and --commit are required outside GitHub Actions"
        )
    try:
        args.function(args)
    except SourceVSAError as error:
        print(f"source-vsa: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
