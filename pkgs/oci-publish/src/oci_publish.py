#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# pylint: disable=too-many-locals, too-many-arguments

"""Publish Ghaf OCI target artifacts."""

import argparse
from collections.abc import Iterator
from contextlib import contextmanager
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any, NoReturn


DETACHED_SIGNATURE_MEDIA_TYPE = "application/vnd.ghaf.signature.v1"
TARGET_ARTIFACT_TYPE = "application/vnd.ghaf.image.v1"
TARGET_CONFIG_MEDIA_TYPE = "application/vnd.ghaf.manifest.v1+json"
TEST_RESULTS_ARTIFACT_TYPE = "application/vnd.ghaf.test-results.v1"
TEST_RESULTS_MEDIA_TYPE = "application/x-tar"
REFERRER_MEDIA_TYPES = {
    "provenance": "application/vnd.in-toto+json",
    "sbom_cyclonedx": "application/vnd.cyclonedx+json",
    "sbom_spdx": "application/spdx+json",
    "sbom_csv": "text/csv",
}
REFERRER_DESCRIPTIONS = {
    "provenance": "SLSA Provenance",
    "sbom_cyclonedx": "CycloneDX SBOM",
    "sbom_spdx": "SPDX SBOM",
    "sbom_csv": "CSV SBOM",
}
REPOSITORY_COMPONENT_PATTERN = re.compile(r"^[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*$")
SOURCE_REF_ANNOTATION = "org.ghaf.source.ref"
TARGET_ANNOTATION = "org.ghaf.target"


def fail(message: str) -> NoReturn:
    """Exit with an error message."""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def read_json(path: Path) -> Any:
    """Load JSON from disk."""
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, data: Any) -> None:
    """Write JSON with stable formatting."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def run_command(
    args: list[str], *, cwd: Path | None = None, stdin_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a command and return the completed process."""
    try:
        return subprocess.run(
            args,
            check=True,
            text=True,
            cwd=cwd,
            input=stdin_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        message = error.stderr.strip() or error.stdout.strip() or str(error)
        fail(message)
    except FileNotFoundError:
        fail(f"command '{args[0]}' is not installed")


def run_oras(args: list[str], *, cwd: Path | None = None) -> dict[str, Any]:
    """Run an ORAS command that returns JSON."""
    result = run_command(["oras", *args, "--format", "json"], cwd=cwd)
    return json.loads(result.stdout)


def annotation_args(annotations: dict[str, str]) -> list[str]:
    """Render annotation CLI arguments."""
    return [
        f"--annotation={key}={value}" for key, value in annotations.items() if value
    ]


def normalize_repository(repository: str) -> str:
    """Normalize and validate an OCI repository path."""
    normalized = repository.strip().lower()
    if not normalized:
        fail("repository must not be empty")

    for component in normalized.split("/"):
        if not REPOSITORY_COMPONENT_PATTERN.fullmatch(component):
            fail(
                f"invalid repository '{repository}': "
                f"component '{component}' does not match OCI naming rules"
            )

    return normalized


@contextmanager
def oras_common_args(
    registry: str, username: str, password: str
) -> Iterator[list[str]]:
    """Return ORAS auth arguments and keep temporary registry config alive."""
    layout_path = os.environ.get("OCI_LAYOUT_PATH", "")
    if layout_path:
        yield ["--oci-layout-path", layout_path]
        return

    if not password:
        fail("OCI_PASSWORD is required when publishing to the registry")

    with tempfile.TemporaryDirectory(prefix="oras-auth-") as registry_config_dir:
        registry_config = Path(registry_config_dir) / "config.json"

        # Use temp login session to avoid exposing OCI_PASSWORD in process arguments.
        run_command(
            [
                "oras",
                "login",
                "-u",
                username,
                "--password-stdin",
                "--registry-config",
                str(registry_config),
                registry,
            ],
            stdin_text=f"{password}\n",
        )

        yield ["--registry-config", str(registry_config)]


def publish_referrer(
    *,
    common_args: list[str],
    subject_reference: str,
    target_dir: Path,
    role: str,
    relpath: str,
    signature_relpath: str | None = None,
) -> dict[str, str]:
    """Attach one referrer artifact."""
    media_type = REFERRER_MEDIA_TYPES[role]

    files = [f"{relpath}:{media_type}"]
    if signature_relpath:
        files.append(f"{signature_relpath}:{DETACHED_SIGNATURE_MEDIA_TYPE}")

    annotations = {
        "org.opencontainers.image.description": REFERRER_DESCRIPTIONS[role],
    }
    output = run_oras(
        [
            "attach",
            *common_args,
            *annotation_args(annotations),
            "--disable-path-validation",
            "--artifact-type",
            media_type,
            subject_reference,
            *files,
        ],
        cwd=target_dir,
    )

    result = {
        "path": relpath,
        "artifact_type": media_type,
        "digest": output["digest"],
    }

    return result


def create_test_results_archive(results_dir: Path, archive_path: Path) -> None:
    """Create a tar archive containing the test-results directory."""
    if not results_dir.is_dir():
        fail(f"test results directory is missing: {results_dir}")

    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w") as archive:
        archive.add(results_dir, arcname=results_dir.name, recursive=True)


def publish_target_artifacts(
    *,
    manifest: dict[str, Any],
    target_dir: Path,
    result_json: Path,
    repository: str,
    common_args: list[str],
    primary_reference: str,
    immutable_tag: str,
    mutable_tags: list[str],
    subject_uses_digest: bool,
) -> int:
    """Publish the primary artifact, referrers, and result metadata."""
    manifest_path = target_dir / "manifest.json"
    result_reference_prefix = f"{primary_reference.rsplit(':', 1)[0]}@"
    target = manifest["target"]
    image = manifest["image"]
    image_path = image["path"]
    image_signature = image["signature"]["path"]
    source = manifest.get("source", {})
    primary_annotations = {
        "org.opencontainers.image.description": "Disk image",
        "org.opencontainers.image.title": target,
        "org.opencontainers.image.source": source.get("repository", ""),
        "org.opencontainers.image.revision": source.get("revision", ""),
        SOURCE_REF_ANNOTATION: source.get("flake_ref", ""),
        TARGET_ANNOTATION: target,
    }

    push_files = [f"{image_path}:application/octet-stream"]
    if image_signature:
        push_files.append(f"{image_signature}:{DETACHED_SIGNATURE_MEDIA_TYPE}")

    primary_output = run_oras(
        [
            "push",
            *common_args,
            *annotation_args(primary_annotations),
            "--disable-path-validation",
            "--artifact-type",
            TARGET_ARTIFACT_TYPE,
            "--config",
            f"{manifest_path}:{TARGET_CONFIG_MEDIA_TYPE}",
            primary_reference,
            *push_files,
        ],
        cwd=target_dir,
    )
    primary_digest = primary_output["digest"]

    attestations = manifest["attestations"]

    referrers: dict[str, Any] = {}
    for role in REFERRER_MEDIA_TYPES:
        relpath = attestations[role]["path"]
        if not relpath:
            continue

        signature_relpath = None
        signature = attestations[role].get("signature")
        if signature:
            signature_relpath = attestations[role]["signature"]["path"]

        referrers[role] = publish_referrer(
            common_args=common_args,
            subject_reference=(
                f"{result_reference_prefix}{primary_digest}"
                if subject_uses_digest
                else primary_reference
            ),
            target_dir=target_dir,
            role=role,
            relpath=relpath,
            signature_relpath=signature_relpath,
        )

    if mutable_tags:
        run_command(["oras", "tag", *common_args, primary_reference, *mutable_tags])

    result = {
        "target": target,
        "repository": repository,
        "immutable_tag": immutable_tag,
        "primary": {
            "artifact_type": TARGET_ARTIFACT_TYPE,
            "media_type": primary_output["mediaType"],
            "digest": primary_digest,
            "reference": f"{result_reference_prefix}{primary_digest}",
            "tag_reference": primary_reference,
        },
        "referrers": referrers,
        "mutable_tags": mutable_tags,
    }
    write_json(result_json, result)

    print(f"[+] Published {target} as {result_reference_prefix}{primary_digest}")
    print(f"[+] Wrote publish result: {result_json}")
    return 0


def publish_target(args: argparse.Namespace) -> int:
    """Publish one target artifact and its referrers."""
    target_dir = Path(args.target_dir).expanduser().resolve()
    manifest_path = target_dir / "manifest.json"
    result_json = Path(args.result_json).expanduser().resolve()

    if not target_dir.is_dir() or not manifest_path.is_file():
        fail("target directory or manifest.json is missing")

    manifest = read_json(manifest_path)
    repository = normalize_repository(args.repository)

    registry = os.environ.get("OCI_REGISTRY", "registry.vedenemo.dev")
    username = os.environ.get("OCI_USERNAME", "jenkins")
    password = os.environ.get("OCI_PASSWORD", "")
    with oras_common_args(registry, username, password) as common_args:
        if os.environ.get("OCI_LAYOUT_PATH", ""):
            primary_reference = f"{repository}:{args.tag}"
            subject_uses_digest = False
        else:
            primary_reference = f"{registry}/{repository}:{args.tag}"
            subject_uses_digest = True
        return publish_target_artifacts(
            manifest=manifest,
            target_dir=target_dir,
            result_json=result_json,
            repository=repository,
            common_args=common_args,
            primary_reference=primary_reference,
            immutable_tag=args.tag,
            mutable_tags=list(args.mutable_tags),
            subject_uses_digest=subject_uses_digest,
        )


def publish_test_results(args: argparse.Namespace) -> int:
    """Publish test results as a referrer attached to a target artifact."""
    results_dir = Path(args.results_dir).expanduser().resolve()

    registry = os.environ.get("OCI_REGISTRY", "registry.vedenemo.dev")
    username = os.environ.get("OCI_USERNAME", "jenkins")
    password = os.environ.get("OCI_PASSWORD", "")
    with oras_common_args(registry, username, password) as common_args:
        with tempfile.TemporaryDirectory(prefix="oci-test-results-") as archive_dir:
            archive_path = Path(archive_dir) / "test-results.tar"
            create_test_results_archive(results_dir, archive_path)

            annotations = {
                "org.opencontainers.image.description": "Test results",
            }
            output = run_oras(
                [
                    "attach",
                    *common_args,
                    *annotation_args(annotations),
                    "--artifact-type",
                    TEST_RESULTS_ARTIFACT_TYPE,
                    args.subject_reference,
                    f"{archive_path.name}:{TEST_RESULTS_MEDIA_TYPE}",
                ],
                cwd=archive_path.parent,
            )

        print(
            f"[+] Published test results for {args.subject_reference}: {output['digest']}"
        )
        return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser."""
    parser = argparse.ArgumentParser(description="Publish Ghaf OCI artifacts")
    subparsers = parser.add_subparsers(dest="command", required=True)

    target_parser = subparsers.add_parser("target", help="publish one target artifact")
    target_parser.add_argument("-d", "--target-dir", required=True)
    target_parser.add_argument("-r", "--repository", required=True)
    target_parser.add_argument("-t", "--tag", required=True)
    target_parser.add_argument("-o", "--result-json", required=True)
    target_parser.add_argument(
        "-m", "--mutable-tag", action="append", default=[], dest="mutable_tags"
    )
    target_parser.set_defaults(handler=publish_target)

    test_results_parser = subparsers.add_parser(
        "test-results", help="attach test results to a target artifact"
    )
    test_results_parser.add_argument("-d", "--results-dir", required=True)
    test_results_parser.add_argument("-s", "--subject-reference", required=True)
    test_results_parser.set_defaults(handler=publish_test_results)

    return parser


def main() -> int:
    """CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
