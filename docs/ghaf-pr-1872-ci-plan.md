<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plan: ghaf-infra changes for Ghaf PR #1872

This document is a handoff-oriented plan for adapting `ghaf-infra` to
[`tiiuae/ghaf#1872`](https://github.com/tiiuae/ghaf/pull/1872).

## Summary

PR `#1872` changes Jetson Orin from:

- one flashable image artifact
- one generic `flash-script`
- optional Jenkins-side UEFI signing of that image

to:

- one per-target flash-images directory:
  `flash-manifest.json`, `esp.img.zst`, `root.img.zst`
- one matching target-specific flasher:
  `packages.x86_64-linux.<target>-flash-script` or `-flash-qspi`
- one flasher invocation that accepts `--flash-images=DIR`
- one drive-selection flag:
  `--target=emmc|nvme|usb`

Expected `ghaf-infra` behavior for Orin:

- Jenkins-side UEFI signing still remains for Orin.
- That UEFI signing applies only to ESP-side payloads, not `root.img.zst`.
- The ESP-side payload set is expected to include bootloader, kernel, and
  `initrd`.
- Detached artifact signatures should cover both flashed artifacts:
  the signed ESP artifact and the root artifact.
- Provenance remains one target-level attestation per build target, not one
  provenance file per flash artifact.
- The upstream manifest now covers artifact discovery, flasher binding,
  target-drive choices, and coarse signing posture.
- The upstream manifest still does not expose the exact Jenkins-side ESP
  signing scope, so `ghaf-infra` would still have to hardcode that part today.

Without the Orin-specific changes in this plan, the current Jenkins flow can
collapse the flash set to `esp.img.zst`, publish only that file, and hand
downstream hardware testing an incomplete flash artifact.

The main remaining blocker is automation compatibility: the current upstream
`--target=usb` flow still expects direct USB/recovery access to the target.
The existing automated lab model writes only the removable USB SSD from the
test agent. Stage 1 is not complete until that gap is closed or the automation
model is explicitly changed.

This plan uses two stages:

- Stage 1: minimum-change support in `ghaf-infra`, using controller artifacts
  as the Orin transport, keeping non-Orin flows unchanged, and skipping the
  misleading single-image OCI path for Orin.
- Stage 2: a follow-up cleanup and OCI model change, where Orin publishes and
  consumes full flash sets through OCI and the Stage 1 controller-artifact path
  can be reduced or removed.

## Main files

- `hosts/hetzci/pipeline-library/vars/pipelineExecution.groovy`
- `hosts/hetzci/pipeline-library/vars/hwTestUtils.groovy`
- `hosts/hetzci/pipeline-library/vars/artifactSupport.groovy`
- `hosts/hetzci/pipelines/ghaf-hw-test.groovy`
- `hosts/hetzci/pipelines/ghaf-hw-test-manual.groovy`
- `scripts/archive-ghaf-release.sh`
- `tests/jenkins/HwTestUtilsTest.groovy`

## Current branch

| Work item | Status | Temporary? | Notes |
| --- | --- | --- | --- |
| Controller-side Orin flash-set detection and preservation of upstream `flash-manifest.json` | Done | No | Jenkins preserves the upstream manifest and records minimal pointers into the artifact tree. |
| Orin hw-test transport via Jenkins artifact-root `IMG_URL` plus `--flash-images=DIR` | Done | Yes | This is the Stage 1 controller-artifact transport and can later be replaced or reduced once OCI carries full flash sets. |
| Target-specific Orin flasher selection for native and cross targets | Done | No | The branch derives the matching x86 flasher attr instead of using the generic `flash-script`. |
| Target-level provenance signing and automated verification for Orin Stage 1 transport | Done | Yes | Jenkins still generates one provenance statement per build target from `unsigned-output`, signs it, and `ghaf-hw-test` verifies it from the artifact root before flashing. |
| Jenkins-side Orin UEFI signing retargeted to `signed-output/` | Partial | Yes | The layout exists, but final `initrd` signer support and manifest-driven scope are still missing. |
| Detached artifact signatures for Orin `esp` and `root` | Done | No | Jenkins signs both flashed artifacts after UEFI-signing the ESP artifact. Orin-aware consumers must verify both signatures, not just the top-level image signature. |
| Skip the broken single-image OCI publish path for Orin | Done | Yes | This prevents publishing a misleading `esp.img.zst`-only OCI artifact until a real multi-artifact OCI model exists. |
| Release packaging for Orin flash sets | Done | No | Release archival preserves `signed-output/` and verifies provenance plus the detached signatures for both Orin flash artifacts. |
| Debug CI plumbing for validating the new Orin flow | Done | Yes | `ci-dbg` temporarily reuses the `ghaf-dev` cache and enables `ghaf-pre-merge-manual`. |
| `ci-yubi` support for signing Orin `initrd` inside the ESP payload set | Not done in this branch | No | This still needs the upstream signer change and a pin update in `ghaf-infra`. |
| Manifest-driven Jenkins-side ESP signing scope | Not done in this branch | No | The upstream manifest has coarse signing posture flags, but not the explicit `bootloader + kernel + initrd` scope needed by `ghaf-infra`. |
| Current lab-compatible USB-media-only automation with no direct target USB/recovery dependency | Blocked outside this branch | No | Current AGX testing shows the upstream flasher still probes the target board and requires recovery-mode USB connection. |
| Full OCI flash-set publish/pull/test-results model | Not done | Yes | This is the longer-term Stage 2 follow-up. |

## Key implementation details

For Orin, Jenkins `manifest.json` should stay minimal and point at the
preserved upstream artifact tree:

```json
{
  "flash_images": {
    "manifest_path": "unsigned-output/flash-manifest.json",
    "unsigned_artifacts_dir": "unsigned-output",
    "signed_artifacts_dir": "signed-output"
  }
}
```

Stage 1 transport and flashing details:

- For Orin, `IMG_URL` means the target artifact root, not a direct image URL.
- `ghaf-hw-test` should derive these from the artifact root:
  - `${IMG_URL}/signed-output/flash-manifest.json`
  - `${IMG_URL}/signed-output/`
  - `${IMG_URL}/attestations/provenance.json`
  - `${IMG_URL}/attestations/provenance.json.sig`
  - `${IMG_URL}/esp.img.zst.sig`
  - `${IMG_URL}/root.img.zst.sig`
- `signed-output/` is the directory that gets flashed.
- Detached artifact signatures stay at the target artifact root.
- `ghaf-hw-test` should build the matching
  `packages.x86_64-linux.<target>-flash-script` from the same Ghaf flake ref
  and run:

```bash
result/bin/initrd-flash-<target> \
  --target=usb \
  --flash-images=/path/to/flash-images
```

Implemented Stage 1 signing and provenance model:

- Provenance signing:
  - Jenkins generates one provenance statement per build target from
    `unsigned-output`.
  - Jenkins signs `attestations/provenance.json` separately from any image
    signing.
  - The automated `ghaf-hw-test` path downloads and verifies that provenance
    before flashing.
  - The manual `ghaf-hw-test-manual` path still does not add an equivalent
    provenance-verification stage here.
  - Stage 1 provenance still attests the build output tree in
    `unsigned-output`, not the final Jenkins-produced `signed-output` flash
    set.
- UEFI signing:
  - Jenkins-side UEFI signing for Orin is still part of the `ghaf-infra`
    flow.
  - `firmware_pkc_signed` in the upstream manifest is upstream firmware state.
    It does not replace Jenkins-side ESP payload signing.
  - UEFI signing applies only to the ESP-side artifact. `root.img.zst` is not
    a UEFI-signing target by itself.
  - The current Stage 1 layout is:
    - preserve upstream output in `unsigned-output/`
    - create the flasher input in `signed-output/`
    - keep detached artifact signatures at the target artifact root
- Detached artifact signatures (`Sign (SLSA) image`):
  - After UEFI signing the ESP artifact, Jenkins produces detached signatures
    for both `signed-output/<esp>` and `signed-output/<root>`.
  - Those `.sig` files live at the target artifact root and are part of the
    Stage 1 consumer contract.
  - The top-level `manifest.image` and `manifest.image.signature` fields stay
    centered on the ESP artifact for compatibility. Orin-aware consumers must
    read `flash_images` and verify both artifact signatures.

## Remaining To Finish Stage 1

Stage 1 is the minimum-change `ghaf-infra` adaptation for PR `#1872`. It is
finished once the remaining items below are addressed and the relevant
validation passes.

Remaining items:

- Extend `uefisign-simple` in `ci-yubi` so the Orin ESP signing path also signs
  `initrd`.
- After that change lands, update the pinned `ci-yubi` input in `ghaf-infra`.
- Extend the upstream manifest so it exposes the explicit Jenkins-side ESP
  signing scope instead of only coarse signing posture.
- Preserve the current USB-media-only CI semantics for `--target=usb`, or
  provide an explicit second mode with a clear selection rule.
- If both direct-device and USB-media-only flows remain supported, make the
  automation select the intended mode explicitly.

### Validation

This validation section is for finishing the remaining Stage 1 work in this
document. Stage 2 will need its own validation plan once the OCI follow-up
work starts.

Controller-side:

- Verify that Orin targets no longer publish or consume only `esp.img.zst`.
- Verify that `ghaf-hw-test` bypasses the legacy single-image `IMG_URL` logic
  for Orin.
- Verify that the target-specific flasher is used for Orin, not the generic
  `packages.x86_64-linux.flash-script`.
- Verify that hw-tests consume `signed-output/`, not the original unsigned
  directory.

Hardware:

- Orin AGX automated USB-media-only flash to USB target drive with no direct
  USB/recovery-mode connection to the target.
- Orin NX automated USB-media-only flash to USB target drive with no direct
  USB/recovery-mode connection to the target, if NX is expected to use the same
  automation model.
- Separate direct-device validation for recovery-mode / QSPI / eMMC / NVMe
  flows if those remain supported as a distinct mode.
- Existing x86 targets still use the unchanged single-image path.

Release:

- Verify that release packaging preserves the full Orin flash set.
- Verify detached Orin artifact signatures and provenance signatures during
  release packaging.

## Stage 2 follow-up

- Publish the full Orin flash set through OCI.
- Pull the full Orin flash set from OCI on the test side.
- Attach provenance and test-results to the flash-set OCI artifact instead of a
  fake single-image subject.
- If stronger provenance-to-artifact binding is needed, verify downloaded flash
  artifact digests against provenance `subject` entries.
- Re-evaluate whether the Stage 1 controller-artifact transport can then be
  reduced to a compatibility path or removed.
