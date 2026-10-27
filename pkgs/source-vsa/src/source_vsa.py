#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""Issue, fetch, inspect, and verify SLSA Source VSA bundles."""

import argparse
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from cryptography import x509
from cryptography.x509.oid import ObjectIdentifier


PREDICATE_TYPE = "https://slsa.dev/verification_summary/v1"
STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
OIDC_ISSUER = "https://token.actions.githubusercontent.com"
BUNDLE_FILENAME = "source-vsa.sigstore.json"
BUNDLE_MEDIA_TYPE = "application/vnd.dev.sigstore.bundle.v0.3+json"
REGISTRY_HOST = "ghcr.io"
REGISTRY_ARTIFACT = "source-vsa"
SLSA_VERSION = "1.2"
SUPPORTED_LEVEL = "SLSA_SOURCE_LEVEL_1"
TRUSTED_WORKFLOW = "tiiuae/ghaf-infra/.github/workflows/issue-source-vsa.yml"
TRUSTED_VERIFIER_ID = f"https://github.com/{TRUSTED_WORKFLOW}"
CALLER_WORKFLOW_PATH = ".github/workflows/source-vsa.yml"


class SourceVSAError(Exception):
    """An expected source VSA operation failed."""


def run_command(
    arguments: list[str],
    *,
    input_text: str | None = None,
    cwd: Path | None = None,
) -> None:
    """Run an external command and retain its output for useful failures."""
    result = subprocess.run(
        arguments,
        check=False,
        cwd=cwd,
        input=input_text,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise SourceVSAError(f"{' '.join(arguments[:2])} failed: {detail}")


def verification_context(args: argparse.Namespace) -> dict[str, Any]:
    """Derive the expected source and issuer identity from command-line inputs."""
    repository = args.repository.lower()

    return {
        "repository": repository,
        "commit": args.commit,
        "verified_level": args.verified_level,
        "issuer_sha": args.issuer_sha,
        "source_ref": args.source_ref,
        "policy_uri": (
            f"https://github.com/{repository}/blob/{args.commit}/{CALLER_WORKFLOW_PATH}"
        ),
        "workflow": f"{repository}/{CALLER_WORKFLOW_PATH}",
        "reference": f"{REGISTRY_HOST}/{repository}/{REGISTRY_ARTIFACT}:{args.commit}",
    }


def create_statement(context: dict[str, Any]) -> dict[str, Any]:
    """Create the canonical Source VSA statement."""
    repository = context["repository"]
    commit = context["commit"]
    return {
        "_type": STATEMENT_TYPE,
        "subject": [{"digest": {"gitCommit": commit}}],
        "predicateType": PREDICATE_TYPE,
        "predicate": {
            "verifier": {"id": TRUSTED_VERIFIER_ID},
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


def read_bundle(bundle_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Read a Sigstore bundle and extract its DSSE payload statement."""
    try:
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        encoded_payload = bundle["dsseEnvelope"]["payload"]
        statement = json.loads(base64.b64decode(encoded_payload, validate=True))
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise SourceVSAError(
            f"invalid Sigstore bundle {bundle_path}: {error}"
        ) from error
    return bundle, statement


def verify_statement(statement: dict[str, Any], context: dict[str, Any]) -> None:
    """Require the canonical statement shape and trusted VSA claims."""
    for field, expected in {
        "_type": STATEMENT_TYPE,
        "predicateType": PREDICATE_TYPE,
    }.items():
        if statement[field] != expected:
            raise SourceVSAError(f"VSA {field} does not match {expected!r}")

    subjects = statement["subject"]
    if len(subjects) != 1:
        raise SourceVSAError("VSA must contain exactly one subject")
    if subjects[0]["digest"] != {"gitCommit": context["commit"]}:
        raise SourceVSAError(
            "VSA subject digest does not match the requested source commit"
        )

    predicate = statement["predicate"]
    if predicate["verifier"]["id"] != TRUSTED_VERIFIER_ID:
        raise SourceVSAError("VSA verifier ID does not match the trusted issuer")
    for field, expected in {
        "resourceUri": f"git+https://github.com/{context['repository']}",
        "verificationResult": "PASSED",
        "verifiedLevels": [context["verified_level"]],
        "slsaVersion": SLSA_VERSION,
    }.items():
        if predicate[field] != expected:
            raise SourceVSAError(f"VSA predicate {field} does not match {expected!r}")
    policy = predicate["policy"]
    if policy["uri"] != context["policy_uri"]:
        raise SourceVSAError("VSA policy URI does not match the caller workflow")
    if (
        "policy_digest" in context
        and policy["digest"]["sha256"] != context["policy_digest"]
    ):
        raise SourceVSAError("VSA policy digest does not match the issuer policy")


def verify_bundle(bundle_path: Path, context: dict[str, Any]) -> None:
    """Verify the Sigstore identity, source claims, and VSA payload."""
    bundle, statement = read_bundle(bundle_path)
    verify_statement(statement, context)
    try:
        certificate = x509.load_der_x509_certificate(
            base64.b64decode(
                bundle["verificationMaterial"]["certificate"]["rawBytes"],
                validate=True,
            )
        )
        (signer_uri,) = certificate.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value.get_values_for_type(x509.UniformResourceIdentifier)
        if not signer_uri.startswith(f"{TRUSTED_VERIFIER_ID}@"):
            raise SourceVSAError(
                "certificate signer does not match the trusted workflow"
            )
        # Fulcio extension OID suffixes and their GitHub OIDC claim mappings:
        # https://github.com/sigstore/fulcio/blob/main/docs/oid-info.md
        for suffix, expected in {
            "9": signer_uri,
            "10": context["issuer_sha"],
            "11": "github-hosted",
            "12": f"https://github.com/{context['repository']}",
            "13": context["commit"],
            "14": context["source_ref"],
            "18": f"https://github.com/{context['workflow']}@{context['source_ref']}",
            "19": context["commit"],
            "20": "push",
        }.items():
            oid = ObjectIdentifier(f"1.3.6.1.4.1.57264.1.{suffix}")
            extension = certificate.extensions.get_extension_for_oid(oid).value
            # These Fulcio extensions are DER UTF8String values.
            value = expected.encode("utf-8")
            length = len(value)
            if length < 128:
                encoded_length = bytes([length])
            else:
                length_bytes = length.to_bytes((length.bit_length() + 7) // 8)
                encoded_length = bytes([0x80 | len(length_bytes)]) + length_bytes
            if extension.value != b"\x0c" + encoded_length + value:
                raise SourceVSAError(
                    f"certificate claim {oid.dotted_string} does not match {expected!r}"
                )
    except (KeyError, TypeError, ValueError, x509.ExtensionNotFound) as error:
        raise SourceVSAError(f"invalid signing certificate: {error}") from error

    # Authenticate the certificate only after its source and issuer policy match.
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
            signer_uri,
            "--certificate-oidc-issuer",
            OIDC_ISSUER,
        ]
    )


def manifest_exists(context: dict[str, Any], actor: str, token: str) -> bool:
    """Check for a commit-tagged manifest using authenticated registry status."""
    registry_repository = f"{context['repository']}/{REGISTRY_ARTIFACT}"
    credentials = base64.b64encode(f"{actor}:{token}".encode()).decode()
    token_query = urlencode(
        {
            "service": REGISTRY_HOST,
            "scope": f"repository:{registry_repository}:pull,push",
        }
    )
    token_request = Request(
        f"https://{REGISTRY_HOST}/token?{token_query}",
        headers={
            "Accept": "application/json",
            "Authorization": f"Basic {credentials}",
            "User-Agent": "source-vsa",
        },
    )
    try:
        with urlopen(token_request, timeout=30) as response:
            token_response = json.load(response)
    except HTTPError as error:
        detail = error.read().decode(errors="replace").strip()
        raise SourceVSAError(
            f"GHCR token request failed with HTTP {error.code}: {detail}"
        ) from error
    except (OSError, json.JSONDecodeError) as error:
        raise SourceVSAError(f"GHCR token request failed: {error}") from error

    registry_token = token_response.get("token") or token_response["access_token"]

    manifest_url = (
        f"https://{REGISTRY_HOST}/v2/"
        f"{quote(registry_repository, safe='/')}/manifests/"
        f"{quote(context['commit'], safe='')}"
    )
    manifest_request = Request(
        manifest_url,
        method="HEAD",
        headers={
            "Accept": "application/vnd.oci.image.manifest.v1+json",
            "Authorization": f"Bearer {registry_token}",
            "User-Agent": "source-vsa",
        },
    )
    try:
        with urlopen(manifest_request, timeout=30):
            return True
    except HTTPError as error:
        if error.code == 404:
            return False
        detail = error.read().decode(errors="replace").strip()
        raise SourceVSAError(
            f"GHCR manifest check failed with HTTP {error.code}: {detail}"
        ) from error
    except OSError as error:
        raise SourceVSAError(f"GHCR manifest check failed: {error}") from error


def pull_bundle(
    reference: str,
    destination: Path,
    *,
    registry_config: Path | None = None,
) -> Path:
    """Pull a bundle from the registry."""
    arguments = ["oras", "pull", "--output", str(destination)]
    if registry_config is not None:
        arguments.extend(["--registry-config", str(registry_config)])
    run_command([*arguments, reference])

    return destination / BUNDLE_FILENAME


def issue(args: argparse.Namespace) -> None:
    """Issue an immutable VSA, or validate the one already at its commit tag."""
    if args.event_name != "push":
        raise SourceVSAError(f"unsupported GitHub event: {args.event_name}")
    try:
        event = json.loads(args.event_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SourceVSAError(f"cannot read GitHub event payload: {error}") from error
    if event["deleted"]:
        raise SourceVSAError("ref deletion events cannot issue a VSA")
    token = os.environ["GITHUB_TOKEN"]
    actor = os.environ["GITHUB_ACTOR"]

    context = verification_context(args)
    if args.ref != context["source_ref"]:
        raise SourceVSAError(f"source ref is not allowed by policy: {args.ref}")
    context["policy_digest"] = hashlib.sha256(
        (Path(os.environ["SOURCE_VSA_SOURCE_DIR"]) / CALLER_WORKFLOW_PATH).read_bytes()
    ).hexdigest()
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
                REGISTRY_HOST,
            ],
            input_text=token,
        )

        authenticated = workdir / "authenticated"
        authenticated.mkdir()
        exists = manifest_exists(context, actor, token)
        if exists:
            bundle = pull_bundle(
                context["reference"],
                authenticated,
                registry_config=registry_config,
            )
        else:
            statement_path = workdir / "statement.json"
            bundle = workdir / BUNDLE_FILENAME
            statement_path.write_text(
                json.dumps(create_statement(context), separators=(",", ":")),
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
        if not exists:
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

        public = workdir / "public"
        public.mkdir()
        # Clear credentials before checking anonymous access.
        registry_config.write_text('{"auths":{}}', encoding="utf-8")
        try:
            public_bundle = pull_bundle(
                context["reference"], public, registry_config=registry_config
            )
        except SourceVSAError as error:
            raise SourceVSAError(
                f"anonymous verification failed: {error}. If this is the first "
                f"publication, make the {context['repository']}/{REGISTRY_ARTIFACT} "
                "package public in GitHub under Package settings > Danger Zone > "
                "Change visibility, then rerun this workflow"
            ) from error
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
    context = verification_context(args)
    verify_bundle(args.bundle, context)


def fetch(args: argparse.Namespace) -> None:
    """Fetch a public VSA bundle and verify it before returning it."""
    context = verification_context(args)
    print(f"source-vsa: fetching {context['reference']}", file=sys.stderr)
    with tempfile.TemporaryDirectory(prefix="source-vsa-") as temporary:
        bundle = pull_bundle(context["reference"], Path(temporary))
        print("source-vsa: verifying bundle", file=sys.stderr)
        verify_bundle(bundle, context)
        shutil.copyfile(bundle, args.bundle)
    print(
        f"source-vsa: verified {context['repository']}@{context['commit']} "
        f"and wrote {args.bundle}",
        file=sys.stderr,
    )


def inspect_bundle(args: argparse.Namespace) -> None:
    """Print the unverified VSA statement embedded in a Sigstore bundle."""
    _, statement = read_bundle(args.bundle)
    print(json.dumps(statement, indent=2))


def parser() -> argparse.ArgumentParser:
    """Build the command-line interface."""
    command_parser = argparse.ArgumentParser(description=__doc__)
    subparsers = command_parser.add_subparsers(dest="command", required=True)

    def common_arguments(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument(
            "--repository",
            default=os.environ.get("GITHUB_REPOSITORY"),
            required=not os.environ.get("GITHUB_REPOSITORY"),
        )
        subparser.add_argument(
            "--commit",
            default=os.environ.get("GITHUB_SHA"),
            required=not os.environ.get("GITHUB_SHA"),
        )
        subparser.add_argument(
            "--verified-level", default=SUPPORTED_LEVEL, choices=[SUPPORTED_LEVEL]
        )
        subparser.add_argument(
            "--source-ref",
            default=os.environ.get("SOURCE_VSA_SOURCE_REF", ""),
            required=not os.environ.get("SOURCE_VSA_SOURCE_REF"),
            help="trusted source branch ref (defaults to SOURCE_VSA_SOURCE_REF)",
        )
        subparser.add_argument(
            "--issuer-sha",
            default=os.environ.get("SOURCE_VSA_ISSUER_SHA", ""),
            required=not os.environ.get("SOURCE_VSA_ISSUER_SHA"),
            help="approved ghaf-infra issuer commit (defaults to SOURCE_VSA_ISSUER_SHA)",
        )

    issue_parser = subparsers.add_parser("issue", help="issue or reuse a Source VSA")
    common_arguments(issue_parser)
    issue_parser.add_argument("--ref", default=os.environ.get("GITHUB_REF"))
    issue_parser.add_argument(
        "--event-name", default=os.environ.get("GITHUB_EVENT_NAME")
    )
    issue_parser.add_argument(
        "--event-path",
        default=os.environ.get("GITHUB_EVENT_PATH"),
        type=Path,
        required=not os.environ.get("GITHUB_EVENT_PATH"),
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
    try:
        args.function(args)
    except (
        SourceVSAError,
        OSError,
        KeyError,
        IndexError,
        TypeError,
        ValueError,
    ) as error:
        print(f"source-vsa: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
