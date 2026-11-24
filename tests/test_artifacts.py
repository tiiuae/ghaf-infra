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


@pytest.mark.parametrize(
    "unsafe_tar", [None, "../escape", "symlink", "symlink-write", "hardlink"]
)
def test_archive_referrer_isolation(tmp_path, unsafe_tar):
    layout = tmp_path / "layout"
    primary = tmp_path / "primary"
    (primary / "output").mkdir(parents=True)
    (primary / "output/disk.img").write_bytes(b"primary image")
    (primary / "manifest.json").write_text(
        json.dumps({"schema_version": 2, "target": "packages.test"})
    )
    subprocess.run(
        [
            "oras",
            "push",
            "--oci-layout-path",
            str(layout),
            "--artifact-type",
            oci_publish.TARGET_ARTIFACT_TYPE,
            "--config",
            "manifest.json:application/json",
            "release-test",
            "output/disk.img",
        ],
        cwd=primary,
        check=True,
    )
    digest = subprocess.check_output(
        ["oras", "resolve", "--oci-layout-path", str(layout), "release-test"], text=True
    ).strip()
    referrer = tmp_path / "referrer"
    (referrer / "attestations").mkdir(parents=True)
    (referrer / "output").mkdir()
    (referrer / "output/disk.img").write_bytes(b"referrer replacement")
    (referrer / "output/injected").write_bytes(b"unattested")
    (referrer / "manifest.json").write_text("{}")
    for name in ("provenance", "release-policy"):
        (referrer / f"attestations/{name}.json").write_text(name)
        (referrer / f"attestations/{name}.json.sig").write_text("signature")
    (referrer / "test-results").mkdir()
    (referrer / "test-results/log.txt").write_text("test log")
    (referrer / "test-results.json").write_text("{}")
    with tarfile.open(referrer / "test-results.tar", "w") as archive:
        archive.add(referrer / "test-results", arcname="test-results")
        archive.add(referrer / "test-results.json", arcname="test-results.json")
        archive.add(referrer / "output", arcname="output")
        if unsafe_tar in ("symlink", "symlink-write", "hardlink"):
            link = tarfile.TarInfo("test-results/link")
            link.type = tarfile.LNKTYPE if unsafe_tar == "hardlink" else tarfile.SYMTYPE
            link.linkname = (
                "../../escape" if unsafe_tar == "symlink" else str(primary / "output")
            )
            archive.addfile(link)
            if unsafe_tar == "symlink-write":
                archive.add(
                    referrer / "output/disk.img", arcname="test-results/link/disk.img"
                )
        elif unsafe_tar:
            archive.add(referrer / "output/injected", arcname=unsafe_tar)
    for artifact_type, paths in (
        (
            "application/vnd.in-toto+json",
            ["attestations/provenance.json", "attestations/provenance.json.sig"],
        ),
        (
            oci_publish.RELEASE_ATTESTATION_ARTIFACT_TYPE,
            [
                "attestations/release-policy.json",
                "attestations/release-policy.json.sig",
            ],
        ),
        (oci_publish.TEST_RESULTS_ARTIFACT_TYPE, ["test-results.tar"]),
        ("application/unexpected", []),
    ):
        subprocess.run(
            [
                "oras",
                "attach",
                "--oci-layout-path",
                str(layout),
                "--artifact-type",
                artifact_type,
                digest,
                *paths,
                "output/disk.img",
                "output/injected",
                "manifest.json",
            ],
            cwd=referrer,
            check=True,
        )
    # Route registry references to a real local OCI layout; no registry or uploads.
    script = (
        (ROOT / "scripts/archive-ghaf-release.sh")
        .read_text()
        .rsplit('\nmain "$@"', 1)[0]
        + r"""
trap 'rm -rf "$TMPDIR"' EXIT
release_targets=(packages.test)
fetch_script=$3
oras() {
  local reference="${!#}"
  if [[ $reference == *@* ]]; then reference="${reference##*@}"; else reference="${reference##*:}"; fi
  if [[ $1 == manifest || $1 == blob ]]; then
    command oras "$1" "$2" --oci-layout-path "$layout" "${@:3:$#-3}" "$reference"
  else
    command oras "$1" --oci-layout-path "$layout" "${@:2:$#-2}" "$reference"
  fi
}
export -f oras
export layout
ghaf-fetch() { bash "$fetch_script" "$@"; }
mkdir "$2-selected"
(cd "$2-selected" && ghaf-fetch --referrer application/vnd.in-toto+json "$OCI_REGISTRY$OCI_REPOSITORY/test:release-test")
pull_artifacts_from_oci release-test
cp -r "$ARTIFACTS/packages.test" "$2"
"""
    )
    pulled = tmp_path / "pulled"
    result = subprocess.run(
        [
            "bash",
            "-c",
            "layout=$1\n" + script,
            "archive-test",
            str(layout),
            str(pulled),
            str(ROOT / "scripts/ghaf-fetch.sh"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert (result.returncode == 0) == (unsafe_tar is None), (
        result.stdout + result.stderr
    )
    if unsafe_tar is None:
        assert (pulled / "output/disk.img").read_bytes() == b"primary image"
        assert not (pulled / "output/injected").exists()
        assert (
            json.loads((pulled / "manifest.json").read_text())["target"]
            == "packages.test"
        )
        assert (pulled / "attestations/provenance.json").read_text() == "provenance"
        assert (
            pulled / "attestations/release-policy.json"
        ).read_text() == "release-policy"
        assert (pulled / "test-results/log.txt").read_text() == "test log"
        assert (pulled / "test-results.json").read_text() == "{}"
    assert (primary / "output/disk.img").read_bytes() == b"primary image"
    selected = tmp_path / "pulled-selected"
    assert (selected / "attestations/provenance.json").read_text() == "provenance"
    assert not (selected / "attestations/release-policy.json").exists()
