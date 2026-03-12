<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Jenkins Hardware Flashing Current State

This is the authoritative source for the current operational status and active
design constraints of Jenkins hardware flashing in `ghaf-infra`.

For the full investigative background, pipeline walkthrough,
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) impact analysis,
integration-path comparison, and detailed
[Path A](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling)
expansion, see the companion
[Jenkins Hardware Flashing Analysis](jenkins-hw-flashing-analysis.md).

## Table of Contents

- [Current Recommendation](#current-recommendation)
- [Phased Rollout Plan](#phased-rollout-plan)
- [Current Production Behavior](#current-production-behavior)
- [Prototype Status](#prototype-status)
  - [What Was Tested](#what-was-tested)
  - [Results](#results)
  - [Ghaf flash-script issues](#ghaf-flash-script-issues)
  - [Remaining Work](#remaining-work)
- [Current Integration Constraints](#current-integration-constraints)
  - [Single `IMG_URL` contract](#single-img_url-contract)
  - [Signature and provenance handling](#signature-and-provenance-handling)

## Current Recommendation

The recommended direction is
[Path A: Delegate flashing to Ghaf-provided tooling](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling):
move target-specific flashing logic out of Jenkins Groovy and have Ghaf provide
a stable flashing contract.

Current status:

- [Path A](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling)
  is the selected integration direction
- [Phase 1](#phase-1-define-the-contract-on-a-single-image-target--validated)
  has been validated on Lenovo X1 in `ghaf-manual`
- [Phase 3](#phase-3-add-orin-split-image-support--not-started) is where
  Orin split-image and multi-artifact signing work begins

For the full integration-path comparison and the signing model for split-image
artifacts, see the companion
[Jenkins Hardware Flashing Analysis](jenkins-hw-flashing-analysis.md).

## Phased Rollout Plan

This rollout plan assumes
[Path A](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling):
delegated flashing via Ghaf-provided tooling.

For the split-image signing choices that become relevant once
[Phase 3](#phase-3-add-orin-split-image-support--not-started) begins, see
[Multi-Artifact Signing Options](jenkins-hw-flashing-analysis.md#multi-artifact-signing-options)
in the analysis document.

| Phase | Focus | Status | Notes |
| --- | --- | --- | --- |
| [Phase&nbsp;1](#phase-1-define-the-contract-on-a-single-image-target--validated) | Single-image delegated flashing | Validated | Lenovo X1 prototype complete in `ghaf-manual` |
| [Phase&nbsp;2](#phase-2-generalize-for-other-current-single-image-targets--not-started) | Generalize delegated flashing to other single-image targets | Not&nbsp;started | Dell Latitude and System76 Darter Pro next |
| [Phase&nbsp;3](#phase-3-add-orin-split-image-support--not-started) | Add Orin split-image support | Not&nbsp;started | Introduces multi-artifact flashing and split-image signing decisions |
| [Phase&nbsp;4](#phase-4-retire-inline-flashing-logic--not-started) | Retire inline Jenkins flashing logic | Not&nbsp;started | Remove legacy `dd`-based paths after delegated flashing is proven |

<a id="phase-1-define-the-contract-on-a-single-image-target--validated"></a>
### Phase 1: Define the contract on a single-image target (VALIDATED)

Prototype validated on Lenovo X1 (see [Prototype Status](#prototype-status)).

- Ghaf's
  [`flash-script`](https://github.com/tiiuae/ghaf/tree/b3436f8ecf50dbbe1146ab70896517c64d324651/packages/pkgs-by-name/flash-script)
  used as delegated flasher
- Closure transferred to test agent at runtime via nix binary cache
- Validated in `ghaf-manual` pipeline on release Jenkins

Remaining: enable in relevant pipelines, drive fixes for upstream issues,
remove workarounds.

<a id="phase-2-generalize-for-other-current-single-image-targets--not-started"></a>
### Phase 2: Generalize for other current single-image targets (NOT STARTED)

- Extend delegated flashing to Dell Latitude and System76 Darter Pro
- Remove target-specific assumptions from the delegated path
- Keep legacy fallback until confidence is high

<a id="phase-3-add-orin-split-image-support--not-started"></a>
### Phase 3: Add Orin split-image support (NOT STARTED)

- Connect the same contract to Orin split-image targets
- Teach the Ghaf flasher to consume split-image manifests
- Validate hardware boot and resize behavior

<a id="phase-4-retire-inline-flashing-logic--not-started"></a>
### Phase 4: Retire inline flashing logic (NOT STARTED)

- Remove inline `dd`-based flashing from `ghaf-hw-test.groovy` and
  `ghaf-hw-test-manual.groovy`
- Simplify image-discovery assumptions in `utils.groovy`

For detailed phase descriptions, see
[Suggested Phased Rollout](jenkins-hw-flashing-analysis.md#suggested-phased-rollout)
in the analysis document.

## Current Production Behavior

Jenkins hardware testing currently assumes one downloadable image file per
target and flashes it with inline Jenkins logic using raw `dd`. Delegated
flashing is not yet the default for any pipeline.

The production flow:

1. The build pipeline discovers a single file matching `*.img`, `*.raw`,
   `*.zst`, or `*.iso` and stores it in `manifest.image`
2. The hardware test job receives a single `IMG_URL` parameter
3. The image is downloaded, optionally decompressed from `.zst`, and written
   directly to the target device with `dd`

There is no representation in the manifest or trigger parameters for a target
that needs multiple image artifacts to be flashed together.

For a detailed walkthrough, see
[Current Jenkins Flashing Flow](jenkins-hw-flashing-analysis.md#current-jenkins-flashing-flow)
in the analysis document.

## Prototype Status

A prototype of delegated flashing
([Path A](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling),
[Phase 1](#phase-1-define-the-contract-on-a-single-image-target--validated))
has been implemented on branch `improve-jenkins-hw-flash` and validated on the
release environment (`ci-release.vedenemo.dev`).

### What Was Tested

The prototype uses Ghaf's existing `packages.x86_64-linux.flash-script` as the
delegated flasher for the Lenovo X1 Carbon Gen11 target, enabled only in the
`ghaf-manual` pipeline.

The implementation:

1. The build pipeline (`utils.groovy`) builds flash-script and exports its nix
   closure as a local binary cache in the artifacts directory
2. The hardware test job (`ghaf-hw-test.groovy`) imports the closure on the
   test agent via `nix copy --from` over HTTPS
3. flash-script handles `.zst` decompression, disk wiping, and image writing
4. The legacy `dd` path is preserved as a fallback when the delegated flash
   parameters are not provided

### Results

Delegated flashing (Lenovo X1):

- flash-script closure transfer via nix binary cache over HTTPS works
  (39 store paths, ~2 seconds)
- flash-script successfully flashed the target device (~6 minutes for a
  full disk image)
- flash-script handles `.zst` decompression natively via streaming
  (`zstdcat | pv | dd`), avoiding an intermediate raw file on the test agent
- flash-script performs ZFS wipe internally, eliminating the inline wipe
  logic currently duplicated in Jenkins for Lenovo X1
- Acroname USB hub mount/unmount and symlink verification work correctly
- Relay boot test passes after delegated flash
- Relay turn-off test passes
- Full pipeline result: SUCCESS (multiple builds validated)

Legacy fallback (System76 Darter Pro):

- The legacy `dd` path remains functional when delegated flash parameters
  are absent
- Full pipeline result: SUCCESS

### Ghaf flash-script issues

Initial testing found two issues in Ghaf's `flash-script` package
(`packages/pkgs-by-name/flash-script/package.nix`):

1. **Missing `gawk` in nix closure.** flash-script declares `awk` as a
   dependency and checks for it at runtime with `command -v`, but `package.nix`
   does not include `gawk` in `runtimeInputs`. The prototype works around this
   with a wrapper script that injects `gawk` into `PATH`. The upstream fix is
   to add `gawk` to the `runtimeInputs` list alongside `coreutils`,
   `util-linux`, `zstd`, and `pv`.

2. **Unconditional ANSI escape codes.** flash-script emits terminal control
   sequences (cursor movement, color codes) regardless of whether stdout is a
   terminal. In Jenkins console output these appear as raw escape sequences.
   The fix is to guard ANSI output with `[ -t 1 ]` or equivalent.

### Remaining Work

Before merging:

- Drive fixes for `tiiuae/ghaf` `flash-script` issues identified (see above)
- Remove temporary `"ghaf-manual"` entry from `release/configuration.nix`
- Remove the `gawk` workaround once the upstream fix lands

Phase 2 and beyond follow the [Phased Rollout Plan](#phased-rollout-plan)
above.

<a id="active-design-constraints"></a>
## Current Integration Constraints

These are the practical constraints any `ghaf-infra` changes must respect.

### Single `IMG_URL` contract

The current trigger from the build pipeline into `ghaf-hw-test` is a single
string parameter:

- `IMG_URL`

If we need multiple image inputs, options include:

- keep one downloadable merged disk image as the main artifact
- extend the manifest and test job API to accept multiple URLs
- keep one URL but point it to a wrapper artifact that knows how to fetch or
  reconstruct the split images

### Signature and provenance handling

The current build pipeline performs three distinct signing operations:

1. SLSA provenance signing
2. optional UEFI signing of the image
3. SLSA image signing

The important ordering detail is:

- UEFI signing happens before SLSA image signing
- the UEFI step replaces the image artifact in place
- the SLSA image signature therefore covers the final image artifact that
  Jenkins publishes and passes to hardware testing

In other words, the chain is:

- raw image
- optional UEFI signing
- SLSA image signing of the resulting artifact

Current non-manual `ghaf-hw-test` behavior verifies:

- one SLSA provenance file and its signature for the target build via
  `policy-checker`
- one SLSA image signature for the selected main image artifact via
  `verify-signature image`

UEFI Secure Boot is not separately verified during the flashing stage. It is
enforced later by the target device firmware at boot time. In practice, the
pipeline routes UEFI-signed builds to the secure-boot-capable hardware path
when available.

The current build pipeline also already writes a per-target `manifest.json`
containing relevant metadata such as:

- selected image path
- whether UEFI signing was applied
- signing key identifiers
- signature file paths

This existing manifest is important prior art for
[Path A](jenkins-hw-flashing-analysis.md#path-a-delegate-flashing-to-ghaf-provided-tooling).
A future flash manifest does not need to start from zero; it can build on the
current artifact/signing metadata model and extend it with flash semantics.

Security gap to keep in mind:

- `ghaf-hw-test` performs provenance and image-signature verification
- `ghaf-hw-test-manual` currently performs no provenance or signature
  verification at all

If Orin produces multiple flash artifacts, the signing model needs to remain
clear:

- is the signed artifact the merged disk image?
- or are `esp.img.zst` and `root.img.zst` individually signed?
- if they are separate, how does the pipeline verify and compose them without
  weakening the trust model?

For current single-image targets, the simplest delegated-flash model is to keep
the same security shape:

- Jenkins publishes one already-final image artifact
- any required UEFI signing has already happened
- SLSA image signing already covers that final artifact
- the delegated flasher receives the already-verified local artifact

The split-image signing question becomes a real design problem only once the
pipeline starts consuming true multi-artifact flash inputs. For concrete
options on how UEFI signing and SLSA image signing could work with
split-image artifacts, see
[Multi-Artifact Signing Options](jenkins-hw-flashing-analysis.md#multi-artifact-signing-options)
in the analysis document.
