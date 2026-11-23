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
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any, NoReturn


DETACHED_SIGNATURE_MEDIA_TYPE = "application/vnd.ghaf.signature.v1"
TARGET_ARTIFACT_TYPE = "application/vnd.ghaf.output.v1"
TARGET_CONFIG_MEDIA_TYPE = "application/vnd.ghaf.manifest.v2+json"
UEFI_PROVENANCE_ARTIFACT_TYPE = "application/vnd.ghaf.uefi-provenance.v1+json"
TEST_RESULTS_ARTIFACT_TYPE = "application/vnd.ghaf.test-results.v1"
TEST_RESULTS_MEDIA_TYPE = "application/x-tar"
RELEASE_ATTESTATION_ARTIFACT_TYPE = "application/vnd.ghaf.release-attestation.v1+json"
SYSUPDATE_MANIFEST_MEDIA_TYPE = "application/vnd.ghaf.ota.manifest.v1+json"
SYSUPDATE_MANIFEST_SIGNATURE_MEDIA_TYPE = (
    "application/vnd.ghaf.ota.manifest-signature.v1+ed25519"
)
SYSUPDATE_KERNEL_MEDIA_TYPE = "application/vnd.ghaf.ota.uki.v1+efi"
SYSUPDATE_ROOT_MEDIA_TYPE = "application/vnd.ghaf.ota.root.v1+raw"
SYSUPDATE_VERITY_MEDIA_TYPE = "application/vnd.ghaf.ota.verity.v1+raw"
SYSUPDATE_MEDIA_TYPES = {
    "root": SYSUPDATE_ROOT_MEDIA_TYPE,
    "verity": SYSUPDATE_VERITY_MEDIA_TYPE,
    "kernel": SYSUPDATE_KERNEL_MEDIA_TYPE,
}
REFERRER_MEDIA_TYPES = {
    "source_vsa": "application/vnd.dev.sigstore.bundle.v0.3+json",
    "provenance": "application/vnd.in-toto+json",
    "uefi_provenance": "application/vnd.in-toto+json",
    "release_policy": RELEASE_ATTESTATION_ARTIFACT_TYPE,
    "sbom_cyclonedx": "application/vnd.cyclonedx+json",
    "sbom_spdx": "application/spdx+json",
    "sbom_csv": "text/csv",
}
# Existing consumers discover Nix build provenance by its artifact type.
REFERRER_ARTIFACT_TYPES = {
    **REFERRER_MEDIA_TYPES,
    "uefi_provenance": UEFI_PROVENANCE_ARTIFACT_TYPE,
}
REFERRER_DESCRIPTIONS = {
    "source_vsa": "SLSA Source VSA",
    "provenance": "SLSA Provenance",
    "uefi_provenance": "SLSA UEFI signing provenance",
    "release_policy": "Ghaf release policy attestation",
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
def oras_publish_context() -> Iterator[tuple[list[str], str, bool]]:
    """Return ORAS arguments and reference mode, keeping auth config alive."""
    layout_path = os.environ.get("OCI_LAYOUT_PATH", "")
    if layout_path:
        yield ["--oci-layout-path", layout_path], "", False
        return

    registry = os.environ.get("OCI_REGISTRY", "registry.vedenemo.dev")
    username = os.environ.get("OCI_USERNAME", "jenkins")
    password = os.environ.get("OCI_PASSWORD", "")
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

        yield ["--registry-config", str(registry_config)], f"{registry}/", True


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
    artifact_type = REFERRER_ARTIFACT_TYPES[role]

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
            artifact_type,
            subject_reference,
            *files,
        ],
        cwd=target_dir,
    )

    result = {
        "path": relpath,
        "artifact_type": artifact_type,
        "digest": output["digest"],
    }

    return result


def publish_attestations(
    *,
    manifest: dict[str, Any],
    common_args: list[str],
    subject_reference: str,
    target_dir: Path,
) -> dict[str, Any]:
    """Attach attestation referrers declared in the build manifest."""
    referrers: dict[str, Any] = {}
    attestations = manifest["attestations"]
    for role in (
        "source_vsa",
        "provenance",
        "uefi_provenance",
        "sbom_cyclonedx",
        "sbom_spdx",
        "sbom_csv",
    ):
        attestation = attestations.get(role)
        if not attestation:
            continue

        relpath = attestation["path"]
        if not relpath:
            continue

        signature_relpath = None
        signature = attestation.get("signature")
        if signature:
            signature_relpath = signature["path"]

        referrers[role] = publish_referrer(
            common_args=common_args,
            subject_reference=subject_reference,
            target_dir=target_dir,
            role=role,
            relpath=relpath,
            signature_relpath=signature_relpath,
        )

    return referrers


def create_test_results_archive(results_dir: Path, archive_path: Path) -> None:
    """Create a tar archive containing the test results."""
    if not results_dir.is_dir():
        fail(f"test results directory is missing: {results_dir}")

    test_results_json = results_dir.parent / "test-results.json"
    if not test_results_json.is_file():
        fail(f"test results summary is missing: {test_results_json}")

    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w") as archive:
        archive.add(results_dir, arcname=results_dir.name, recursive=True)
        archive.add(test_results_json, arcname=test_results_json.name)


def output_files(
    path: Path, target_dir: Path, ancestors: frozenset[Path] = frozenset()
) -> list[Path]:
    """Follow output links only within the store or this target, rejecting cycles."""
    try:
        resolved = path.resolve(strict=True)
        if not (
            resolved.is_relative_to("/nix/store") or resolved.is_relative_to(target_dir)
        ):
            fail(f"output path escapes the Nix store and target directory: {path}")
        mode = resolved.stat().st_mode
        if stat.S_ISREG(mode):
            return [path]
        if not stat.S_ISDIR(mode):
            fail(f"output path is not a regular file or directory: {path}")
        if resolved in ancestors:
            fail(f"output directory cycle: {path}")
        files = []
        for child in sorted(path.iterdir()):
            files.extend(output_files(child, target_dir, ancestors | {resolved}))
        return files
    except (OSError, RuntimeError) as error:
        fail(f"invalid output path {path}: {error}")


def validate_output(args: argparse.Namespace) -> int:
    """Validate an output before collection, hashing, or signing follows its links."""
    output_files(Path(args.path), Path(args.target_dir).resolve(strict=True))
    return 0


def validate_upload_files(
    manifest: dict[str, Any], target_dir: Path, upload_paths: list[str]
) -> None:
    """Check every explicit upload, including attestation and OTA payload paths."""
    for attestation in manifest["attestations"].values():
        if attestation.get("path"):
            upload_paths.append(attestation["path"])
        if signature := attestation.get("signature"):
            upload_paths.append(signature["path"])
    for relpath in upload_paths:
        path = Path(relpath)
        if path.is_absolute() or ".." in path.parts:
            fail(f"artifact path must be relative to the target directory: {relpath}")
        if output_files(target_dir / path, target_dir) != [target_dir / path]:
            fail(f"artifact path must identify a regular file: {relpath}")


def publish_target(args: argparse.Namespace) -> int:
    """Publish the complete output directory and its attestation referrers."""
    target_dir = Path(args.target_dir).expanduser().resolve()
    result_json = Path(args.result_json).expanduser().resolve()
    manifest = read_json(target_dir / "manifest.json")
    output_dir = target_dir / manifest["output"]["path"]
    if not output_dir.is_dir():
        fail(f"output directory is missing: {output_dir}")

    target = manifest["target"]
    source = manifest["source"]
    annotations = {
        "org.opencontainers.image.description": "Target output",
        "org.opencontainers.image.title": target,
        "org.opencontainers.image.source": source.get("repository", ""),
        "org.opencontainers.image.revision": source.get("revision", ""),
        SOURCE_REF_ANNOTATION: manifest["source"]["flake_ref"],
        TARGET_ANNOTATION: target,
    }
    files = []
    media_types = {}
    if image_signature := manifest.get("image", {}).get("signature", {}).get("path"):
        media_types[image_signature] = DETACHED_SIGNATURE_MEDIA_TYPE

    artifact_type = TARGET_ARTIFACT_TYPE
    config_path, config_media_type = "manifest.json", TARGET_CONFIG_MEDIA_TYPE
    sysupdate_result = None
    if sysupdate := manifest.get("sysupdate"):
        # Preserve the OTA registry format consumed by the updater.
        artifact_type = config_media_type = SYSUPDATE_MANIFEST_MEDIA_TYPE
        config_path = sysupdate["path"]
        output_files(target_dir / config_path, target_dir)
        ota = read_json(target_dir / config_path)
        annotations.update(
            {
                "org.opencontainers.image.description": "OTA update",
                "org.ghaf.ota.version": ota["version"],
                "org.ghaf.ota.system": ota["system"],
            }
        )
        if signature_path := sysupdate.get("signature", {}).get("path"):
            media_types[signature_path] = SYSUPDATE_MANIFEST_SIGNATURE_MEDIA_TYPE
            files.append(signature_path)
        ota_files = []
        for role in ("kernel", "root", "verity"):
            media_type = SYSUPDATE_MEDIA_TYPES[role]
            path = (Path(config_path).parent / ota[role]["file"]).as_posix()
            media_types[path] = media_type
            files.append(path)
            ota_files.append({"role": role, "path": path, "media_type": media_type})
        sysupdate_result = {
            "version": ota["version"],
            "system": ota["system"],
            "root_verity_hash": ota["root_verity_hash"],
            "manifest_path": config_path,
            "files": ota_files,
        }
    else:
        files = [
            path.relative_to(target_dir).as_posix()
            for path in output_files(output_dir, target_dir)
        ]

    validate_upload_files(manifest, target_dir, [config_path, *files])

    repository = normalize_repository(args.repository)
    with oras_publish_context() as (common_args, reference_prefix, subject_uses_digest):
        primary_reference = f"{reference_prefix}{repository}:{args.primary_tag}"
        output = run_oras(
            [
                "push",
                *common_args,
                *annotation_args(annotations),
                "--disable-path-validation",
                "--artifact-type",
                artifact_type,
                "--config",
                f"{config_path}:{config_media_type}",
                primary_reference,
                *[
                    f"{path}:{media_types.get(path, 'application/octet-stream')}"
                    for path in files
                ],
            ],
            cwd=target_dir,
        )
        reference = f"{reference_prefix}{repository}@{output['digest']}"
        referrers = publish_attestations(
            manifest=manifest,
            common_args=common_args,
            subject_reference=reference if subject_uses_digest else primary_reference,
            target_dir=target_dir,
        )
        if args.tags:
            run_command(["oras", "tag", *common_args, primary_reference, *args.tags])

    result = {
        "target": target,
        "repository": repository,
        "primary_tag": args.primary_tag,
        "primary": {
            "artifact_type": artifact_type,
            "media_type": output["mediaType"],
            "digest": output["digest"],
            "reference": reference,
            "tag_reference": primary_reference,
        },
        "referrers": referrers,
        "tags": args.tags,
    }
    if sysupdate_result:
        result["sysupdate"] = sysupdate_result
    write_json(result_json, result)
    print(f"[+] Published {target} as {reference}")
    print(f"[+] Wrote publish result: {result_json}")
    return 0


def publish_test_results(args: argparse.Namespace) -> int:
    """Publish test results as a referrer attached to a target artifact."""
    results_dir = Path(args.results_dir).expanduser().resolve()

    with oras_publish_context() as (
        common_args,
        _reference_prefix,
        _subject_uses_digest,
    ):
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


def publish_release_attestation(args: argparse.Namespace) -> int:
    """Publish a release policy attestation as a referrer."""
    target_dir = Path(args.target_dir).expanduser().resolve()
    relpath = "attestations/release-policy.json"
    signature_relpath = "attestations/release-policy.json.sig"

    with oras_publish_context() as (
        common_args,
        _reference_prefix,
        _subject_uses_digest,
    ):
        result = publish_referrer(
            common_args=common_args,
            subject_reference=args.subject_reference,
            target_dir=target_dir,
            role="release_policy",
            relpath=relpath,
            signature_relpath=signature_relpath,
        )

    print(
        "[+] Published release policy attestation for "
        f"{args.subject_reference}: {result['digest']}"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser."""
    parser = argparse.ArgumentParser(description="Publish Ghaf OCI artifacts")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser(
        "validate-output", help="check output paths before following links"
    )
    validate_parser.add_argument("--target-dir", required=True)
    validate_parser.add_argument("path")
    validate_parser.set_defaults(handler=validate_output)

    target_parser = subparsers.add_parser("target", help="publish one target artifact")
    target_parser.add_argument("-d", "--target-dir", required=True)
    target_parser.add_argument("-r", "--repository", required=True)
    target_parser.add_argument("--primary-tag", required=True)
    target_parser.add_argument("-o", "--result-json", required=True)
    target_parser.add_argument("-t", "--tag", action="append", default=[], dest="tags")
    target_parser.set_defaults(handler=publish_target)

    test_results_parser = subparsers.add_parser(
        "test-results", help="attach test results to a target artifact"
    )
    test_results_parser.add_argument("-d", "--results-dir", required=True)
    test_results_parser.add_argument("-s", "--subject-reference", required=True)
    test_results_parser.set_defaults(handler=publish_test_results)

    release_attestation_parser = subparsers.add_parser(
        "release-attestation", help="attach release policy attestation"
    )
    release_attestation_parser.add_argument("-d", "--target-dir", required=True)
    release_attestation_parser.add_argument("-s", "--subject-reference", required=True)
    release_attestation_parser.set_defaults(handler=publish_release_attestation)

    return parser


def main() -> int:
    """CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
