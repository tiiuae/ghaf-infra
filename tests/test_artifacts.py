# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""Regressions for output traversal, OCI publishing, and archive formats."""

# pylint: disable=missing-function-docstring

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tarfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "oci_publish", ROOT / "pkgs/oci-publish/src/oci_publish.py"
)
oci_publish = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oci_publish)


@pytest.mark.parametrize("destination", ["../../secret", ".", "missing"])
def test_reject_unsafe_output(tmp_path, destination):
    target = tmp_path / "target"
    output = target / "output"
    output.mkdir(parents=True)
    (tmp_path / "secret").write_text("private")
    (output / "link").symlink_to(output / destination)
    with pytest.raises(SystemExit, match="1"):
        oci_publish.output_files(output, target)


def test_publish_round_trip_without_provenance(tmp_path, monkeypatch):
    target = tmp_path / "target"
    (target / "output/nested").mkdir(parents=True)
    (target / "unsigned.img").write_bytes(b"image")
    (target / "output/disk.img").symlink_to(target / "unsigned.img")
    (target / "output/nested/extra.txt").write_bytes(b"extra")
    (target / "manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 2,
                "target": "packages.test",
                "source": {
                    "repository": "https://example.com/ghaf",
                    "revision": "abc123",
                    "flake_ref": "ref",
                },
                "output": {"path": "output"},
                "image": {"path": "output/disk.img"},
                "attestations": {},
            }
        )
    )
    monkeypatch.setenv("OCI_LAYOUT_PATH", str(tmp_path / "layout"))
    result = tmp_path / "result.json"
    oci_publish.publish_target(
        argparse.Namespace(
            target_dir=target,
            result_json=result,
            repository="ghaf/test",
            primary_tag="test",
            tags=[],
        )
    )
    digest = json.loads(result.read_text())["primary"]["digest"]
    layout_args = ["--oci-layout-path", str(tmp_path / "layout")]
    manifest = json.loads(
        subprocess.check_output(["oras", "manifest", "fetch", *layout_args, digest])
    )
    assert manifest["annotations"]["org.opencontainers.image.revision"] == "abc123"
    assert (
        manifest["annotations"]["org.opencontainers.image.source"]
        == "https://example.com/ghaf"
    )
    pulled = tmp_path / "pulled"
    subprocess.run(
        ["oras", "pull", *layout_args, "-o", str(pulled), digest], check=True
    )
    assert (pulled / "output/disk.img").read_bytes() == b"image"
    assert (pulled / "output/nested/extra.txt").read_bytes() == b"extra"


@pytest.mark.parametrize("version,oci_tag", [(1, ""), (2, "release-test"), (2, "")])
def test_release_archive(tmp_path, version, oci_tag):
    target = tmp_path / "artifacts/packages.test"
    prefix = "images" if version == 1 else "output"
    (target / prefix).mkdir(parents=True)
    image = {
        "path": f"{prefix}/disk.img",
        "signature": {"path": f"{prefix}/disk.img.sig"},
    }
    (target / image["path"]).write_bytes(b"image")
    (target / image["signature"]["path"]).write_bytes(b"signature")
    manifest = (
        {"images": [image]}
        if version == 1
        else {
            "schema_version": 2,
            "output": {"path": "output"},
            "image": image,
        }
    )
    (target / "manifest.json").write_text(json.dumps(manifest))
    script = (
        (ROOT / "scripts/archive-ghaf-release.sh")
        .read_text()
        .rsplit('\nmain "$@"', 1)[0]
    )
    # Exercise packaging without signature tooling or storage access.
    script += """
trap 'rm -rf "$TMPDIR"' EXIT
release_targets=(packages.test)
OCI_TAG=$2
verify_signatures() { :; }
tree() { :; }
prepare_artifacts "$1"
cp "$TMPDIR/archived/test.tar" "$3"
"""
    archive = tmp_path / "result.tar"
    result = subprocess.run(
        [
            "bash",
            "-c",
            script,
            "archive-test",
            str(target.parent),
            oci_tag,
            str(archive),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if version == 2 and not oci_tag:
        assert result.returncode == 1
        assert "require OCI retrieval (-o)" in result.stdout + result.stderr
    else:
        assert result.returncode == 0, result.stdout + result.stderr
        with tarfile.open(archive) as handle:
            assert (
                handle.extractfile(f"packages.test/{image['path']}").read() == b"image"
            )
            assert (
                handle.extractfile(f"packages.test/{image['signature']['path']}").read()
                == b"signature"
            )
