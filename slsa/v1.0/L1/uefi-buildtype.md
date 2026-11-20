<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Build type: Jenkins UEFI signing v1

Build type URI:
`https://github.com/tiiuae/ghaf-infra/blob/main/slsa/v1.0/L1/uefi-buildtype.md`.

This build type describes the UEFI signing step performed by the Ghaf Jenkins
pipeline after a Nix build. It uses the SLSA Provenance v1 predicate
(`https://slsa.dev/provenance/v1`) in an in-toto Statement v1.

The Nix build provenance remains in `attestations/provenance.json`. The UEFI
statement is written to `attestations/uefi-provenance.json` and signed using the
existing provenance signing key, with a detached signature at
`attestations/uefi-provenance.json.sig`. The target manifest records its path
and signature metadata under `attestations.uefi_provenance`.

UEFI provenance is generated only when UEFI signing succeeds and provenance is
enabled for the target. Targets with signing disabled, no image, no UEFI signing
request, or `provenance: false` do not produce it. The main image is signed
separately; provenance-chain verification is not performed by the pipeline.

## Inputs

`buildDefinition.externalParameters.input` is the signer input path relative to
the unsigned Nix output directory. It identifies the disk/installer image, or
the sysupdate manifest for a sysupdate target. For Orin targets it is `.`,
identifying the entire unsigned output directory passed to `uefisign-orin`.

The platform records these `internalParameters`:

- `signer`: the command selected by the pipeline: `uefisign`, `uefisign-orin`,
  or `uefi-sign-sysupdate`.
- `signing_key`: the PKCS#11 URI actually selected for UEFI signing.

`resolvedDependencies` contains:

1. The unsigned output descriptor from the Nix build provenance, selected by its
   resolved store-path URI. Its digest is copied unchanged so the two statements
   link by digest. For ordinary Nix directory outputs this is the SHA-256 of the
   NAR serialization, **not** a hash of an individual image file.
2. The Nix build provenance file, identified by its bundle-relative URI and
   SHA-256 of its exact bytes.
3. The resolved signer executable, identified by its absolute Nix store path and
   SHA-256 of its file contents. The store path and script contents identify the
   implementation and its packaged references.
4. The UEFI certificate file supplied to the signer, identified by its path and
   SHA-256 of its file contents.

The original statement supplies the source and Nix build metadata. The UEFI
statement describes the subsequent transformation without copying those fields.

## Outputs and execution

Each `subject` is a file returned by the signer, identified by its path relative
to the signer's output directory in `name` and the SHA-256 of its exact bytes in
`digest.sha256`. The pipeline recursively inventories that directory immediately
after the signer succeeds. Nested paths and companion files are included
without filtering by extension. The complete signer output is retained under
`output/`, preserving the subject names, including any `signed_` prefix.
Subject names are relative to that directory, not to `manifest.json`.

Only signer outputs are subjects. Temporary OTA verification files, the OTA
manifest signature created separately by Jenkins, and detached CI image
signatures are produced after this inventory and are not included.

The pipeline invokes the selected signer with the configured certificate,
selected UEFI key URI, unsigned input and temporary output directory. It hashes
every returned file before adding OTA and main-image signatures. The pipeline
then writes the statement and signs it with the provenance key.

`runDetails.builder.id` is the Jenkins controller URL. Its `version.ghaf-infra`
is the controller's NixOS configuration revision, identifying the infrastructure
implementation. `metadata.invocationId` is the Jenkins build URL. `startedOn`
and `finishedOn` are UTC timestamps covering UEFI signer execution, before
output hashing, subsequent OTA signing and provenance generation.

The statement and its signature are published as an OCI referrer with artifact
type `application/vnd.ghaf.uefi-provenance.v1+json`. The statement layer uses
`application/vnd.in-toto+json`. The distinct artifact type preserves existing
consumers that discover Nix build provenance by artifact type. Local artifacts
and release archives retain both statements under `attestations/`.
