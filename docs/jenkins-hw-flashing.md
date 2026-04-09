<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Jenkins Hardware Flashing

This document is the authoritative description of current Jenkins hardware
flashing in `ghaf-infra`, the active upstream constraints, and the recommended
next implementation steps for Orin support.

## Current Production Behavior

`ghaf-infra` main already uses delegated flashing for the automated
hardware-test path.

### Build-to-test handoff

`hosts/hetzci/pipelines/modules/utils.groovy`:

1. builds the target
2. discovers one primary image artifact (`*.img`, `*.raw`, `*.zst`, `*.iso`)
3. publishes that path as `manifest.image`
4. passes the downstream job:
   - `IMG_URL`
   - `GHAF_FLAKE_REF`

For pre-merge jobs, the flake ref is set to the GitHub PR merge ref so test
agents rebuild the flasher from the same merged view Jenkins built.

### Automated flashing job

`hosts/hetzci/pipelines/ghaf-hw-test.groovy`:

1. verifies provenance in a dedicated `Verify provenance` stage
2. downloads the image and verifies its SLSA image signature
3. resolves or derives `GHAF_FLAKE_REF`
4. builds `packages.x86_64-linux.flash-script` on the test agent
5. runs that flasher against the downloaded image

### Manual flashing job

`hosts/hetzci/pipelines/ghaf-hw-test-manual.groovy` uses the same delegated
model by default, with two differences:

- it accepts an explicit `GHAF_FLAKE_REF` override for cases where `IMG_URL`
  alone is not enough
- it still keeps `USE_LEGACY_DD_FLASH` as a manual override for troubleshooting
  and for image formats that `flash-script` does not support

## Current Ghaf-side Status

Last verified 2026-04-09 against:

- `tiiuae/ghaf` `main` at `ea7fb142a2b10a007f34375cac7252f72f0e7551`
- `tiiuae/ghaf` PR#1872 head at `6f6fcf2e9a9566fb14718aa13d4373eef35089b8`
- `tiiuae/ghaf` PR#1872 merge ref at `9b14acd3bf528115489a6b30391fc653c0c7acf9`

At `main` commit `ea7fb142a2b10a007f34375cac7252f72f0e7551`, Ghaf is compatible
with the present Jenkins flow:

- Orin is still on the legacy single-image publishing path
- Orin target-specific `*-flash-script` and `*-flash-qspi` outputs still exist
- generic `flash-script` remains available as a packaged Ghaf output

`flash-script` in `ghaf` main also includes:

- `gawk` in the runtime closure
- clean non-TTY Jenkins log output
- `bmaptool`-based flashing improvements for compressed images

Current `ghaf-infra` release archiving and publication are still single-image
oriented as well. That path must be updated alongside hardware testing once
Jetson targets stop publishing one canonical image.

## What PR#1872 Changes

[`tiiuae/ghaf` PR#1872](https://github.com/tiiuae/ghaf/pull/1872) was reviewed
here at head commit `6f6fcf2e9a9566fb14718aa13d4373eef35089b8` (GitHub merge
ref `9b14acd3bf528115489a6b30391fc653c0c7acf9`). It keeps the two-stage initrd
flash direction alive for Jetson Orin, though `ghaf` `main` commit
`ea7fb142a2b10a007f34375cac7252f72f0e7551` had not merged it yet.

From the PR summary and discussion, the relevant behavior change is:

- Orin would move from one ready-to-flash image to separate `esp.img.zst` and
  `root.img.zst` payloads
- flashing would become a two-stage flow:
  - device-side initrd/RCM stage for firmware and device setup
  - host-side stage that detects exposed storage, creates GPT, and writes the
    partition payloads
- the PR also carries boot and serial fixes needed for that flow
- the PR exports target-specific `*-flash-script` packages for x86_64, plus
  QSPI-only variants

The Apr 8, 2026 review discussion also notes that test automation still needs
updated flashing support before the PR can merge.

## Why NVIDIA Pushes This Direction

The NVIDIA references below explain why this is not just a Ghaf-internal
refactor.

- NVIDIA documents initrd flashing through `l4t_initrd_flash.sh` as the
  supported path for external-storage Jetson workflows, including the Orin NX
  and Orin Nano cases that matter here and secure-boot examples using
  `--uefi-keys`
- NVIDIA's production guidance explicitly ties initrd flashing to
  OTA-compatible layouts for external-storage systems

Inference: PR#1872's split-artifact, two-stage flow follows the vendor model
for Orin external storage.

## Integration Constraints

If PR#1872 lands, `ghaf-infra` still needs more work because production
automation assumes one primary image artifact, one `IMG_URL`, one
image-signature verification flow, and one flash input passed to the Ghaf
flasher.

### Single-artifact handoff

The build pipeline still triggers `ghaf-hw-test` with one primary image URL.
There is no representation for a target that requires multiple flash artifacts
to be consumed together, what role each artifact plays, or which flasher
entrypoint automation should select.

### Signature and provenance handling

Today the build pipeline performs three distinct signing operations in order:

1. SLSA provenance signing for the build attestation
2. optional UEFI signing of the selected image artifact
3. SLSA image signing of the final post-UEFI image artifact

The non-manual `ghaf-hw-test` job verifies provenance first and then the
selected image artifact's signature before flashing. The build pipeline also
writes per-target `manifest.json` metadata containing the selected image path,
signature paths, and UEFI-signing status.

`ghaf-infra` already solved flasher provenance and delivery for the current
model, but not multi-artifact handoff. A PR#1872-style output therefore still
needs a new contract for multiple flash inputs, artifact roles, flasher
selection, and release handling.

### Flasher package interface

PR#1872 also adds target-specific Jetson flasher outputs, while current Jenkins
hardware testing still builds the generic `packages.x86_64-linux.flash-script`
package.

That means multi-artifact support also needs one of the following:

- a single supported higher-level flasher entrypoint that Jenkins can keep
  calling for every target
- an explicit target-to-flasher mapping in the automation contract so Jenkins
  selects the correct Jetson flasher package

## Signing Impacts

Signing is still one of the core unresolved parts of the PR#1872 integration.

The three signing layers described above do not all change in the same way for
the future Orin path.

### SLSA provenance

SLSA provenance is still fundamentally per build. Whether the build publishes
one image or several flash artifacts, the attestation model does not need to
become partition-specific.

The current trust model also matters here: today policy checks validate the
provenance signature, builder, repo, and freshness, but they do not bind a
downloaded image digest back to a provenance `subject`. Because of that, simply
creating separate provenance files per child image would add little by itself.

Current recommendation for provenance:

- keep one provenance statement per build target
- if stronger artifact binding is required later, extend the consumer path to
  validate downloaded artifact digests against provenance subjects

### UEFI signing

UEFI signing is different. In the split-image shape described by PR#1872, the
UEFI-loaded content naturally lives in the ESP artifact, not in the rootfs
artifact. The question is not "how do we sign every artifact", but "which
artifact carries the EFI payloads and how is that artifact signed".

The clean long-term fit is:

- UEFI signing applies to the ESP payload or ESP image
- the root image is still part of the flash set, but not a UEFI-signing target
  by itself

### SLSA image signatures

For the SLSA image-signing layer, there are three realistic models:

1. Per-artifact signatures:
   Sign `esp.img.zst` and `root.img.zst` independently and verify each one in
   the test job. This matches the actual consumer contract and keeps the
   canonical trust objects aligned with what flashing consumes.
2. Signed flash manifest:
   Sign one manifest that lists every flash artifact plus checksums and roles.
   This can be a useful wrapper, but it should augment rather than replace
   separately signed canonical artifacts.
3. Compatibility merged image:
   Merge the split artifacts into one compatibility image and keep today's
   single-image UEFI + SLSA signing flow for that merged output. This is a
   plausible transition path, but weaker as the long-term native model because
   it hides the real artifact structure.

Current recommendation:

- canonical trust model: keep one target-level provenance statement and sign
  each consumed Jetson image separately
- optional enhancement: sign a flash manifest as well, if Ghaf exposes one, so
  the artifact set also has an explicit signed wrapper
- avoid making an early merged image or bundle the only canonical artifact
- acceptable transition path: create a compatibility merged image while the
  native multi-artifact contract is still being implemented

## Recommendation

Keep the current `GHAF_FLAKE_REF`-based delegated flashing model. The next step
is to extend the handoff contract, not to move partition-layout or
target-specific merge logic into Jenkins Groovy.

Recommended model:

- keep one provenance statement per build target
- treat `esp.img.zst` and `root.img.zst` as separate canonical artifacts
- sign both images separately
- do not make an early bundle the only trusted or canonical artifact

Practical recommendation for `ghaf-infra`:

1. Ghaf should provide one supported automation-facing flashing contract for
   the PR#1872 artifact shape.
2. `ghaf-infra` should pass structured flash metadata to the test job instead
   of trying to infer the right behavior from one `IMG_URL`. A suitable shape
   would be an artifact-set model such as `artifacts.images[]`, where each item
   declares at least a role, path, and signature for one canonical flash input.
3. Verification and signing should treat `esp.img.zst` and `root.img.zst` as
   separately signed canonical artifacts under one target-level provenance
   statement, and Jenkins should verify both image signatures before any Jetson
   flashing starts.
4. If archive or release UX needs a convenience bundle, it should remain a
   secondary wrapper around the separately signed images, not replace them as
   the canonical trust objects.
5. If stronger provenance-to-artifact binding is needed, the consumer path
   should verify downloaded artifact digests against provenance subjects.

## Likely Implementation Plan

The dependency order is straightforward: Ghaf defines the automation contract
first, `ghaf-infra` consumes it second, and both sides validate the transition
last.

### 1. Ghaf-side contract definition

- Decide whether automation should consume:
  - a single higher-level flasher entrypoint, or
  - target-specific flasher outputs plus explicit artifact metadata
- Define the artifact contract for two-stage Orin flashing
- Make the expected artifact roles explicit
- Define how UEFI and SLSA signing should work for multi-artifact output
- Expose the correct Jetson flasher entrypoint or explicit target-to-flasher
  mapping for automation use

### 2. `ghaf-infra` integration

1. Update the artifact manifest schema in
   `hosts/hetzci/pipelines/modules/utils.groovy`.
2. Update image discovery logic to support multiple output images for Jetson
   targets.
3. Sign both Jetson images separately.
4. Preserve single target-level provenance generation and signing.
5. Update `scripts/archive-ghaf-release.sh` to verify and package multiple
   images and signatures.
6. Update `hosts/hetzci/pipelines/ghaf-hw-test.groovy` for Jetson targets so
   it:
   - obtains all declared flash artifacts
   - verifies all declared image signatures before flashing
   - uses the Ghaf-provided Jetson flash flow and correct flasher entrypoint
7. Update any archive or publication assumptions that each target has exactly
   one image artifact.

### 3. Validation and transition

- Keep the current single-image path working while PR#1872 support is being
  validated
- Validate the full Orin flow in test automation before upstream merge
- If stronger provenance-to-artifact binding is later required, extend the
  consumer path to validate downloaded artifact digests against provenance
  `subject` entries

## Summary

Current production already handles single-image delegated flashing through
`GHAF_FLAKE_REF`.

The remaining gap is that future Orin two-stage output from
[`tiiuae/ghaf` PR#1872](https://github.com/tiiuae/ghaf/pull/1872)
still needs an explicit multi-artifact automation contract, including a clear
UEFI- and SLSA-signing model and a concrete `ghaf-infra` implementation path
for manifest, archive, and hardware-test updates.

## Primary Sources

- [`tiiuae/ghaf` PR#1872](https://github.com/tiiuae/ghaf/pull/1872)
- [NVIDIA Jetson Linux Developer Guide, Flashing Support (r38.2)](https://docs.nvidia.com/jetson/archives/r38.2/DeveloperGuide/SD/FlashingSupport.html)
- [NVIDIA Jetson Linux Developer Guide, Flashing Support (r36.4.3)](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/FlashingSupport.html)
- [NVIDIA Jetson Linux Developer Guide, Secure Boot (r36.4.3)](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/Security/SecureBoot.html)
- [NVIDIA Jetson Linux Developer Guide, Quick Start (r36.2)](https://docs.nvidia.com/jetson/archives/r36.2/DeveloperGuide/IN/QuickStart.html)
