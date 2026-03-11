<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Jenkins Hardware Flashing Notes

This note captures the current Jenkins hardware flashing behavior in
`ghaf-infra` and the impact observed while reviewing
[`tiiuae/ghaf` PR #1787](https://github.com/tiiuae/ghaf/pull/1787),
"NVidia AGX: 2 stage initrd install".

The goal is to document what the current pipeline actually does, what it
assumes about image artifacts, and where those assumptions conflict with the
new Orin flashing model introduced in the PR.

## Table of Contents

- [Executive Summary](#executive-summary)
- [Scope](#scope)
- [Current Jenkins Flashing Flow](#current-jenkins-flashing-flow)
- [What Ghaf Already Provides Today](#what-ghaf-already-provides-today)
- [What PR #1787 Changes in Ghaf](#what-pr-1787-changes-in-ghaf)
- [Findings From The PR Review](#findings-from-the-pr-review)
- [Detailed Pipeline Constraints](#detailed-pipeline-constraints)
- [Likely Directions For Follow-Up Work](#likely-directions-for-follow-up-work)
- [Recommended Immediate Next Steps](#recommended-immediate-next-steps)
- [Expanding Option C](#expanding-option-c)
  - [What Ghaf Needs To Provide Next](#what-ghaf-needs-to-provide-next)
  - [What ghaf-infra Needs To Change](#what-ghaf-infra-needs-to-change)
  - [Suggested Phased Rollout](#suggested-phased-rollout)
  - [Proposed Immediate Work Split](#proposed-immediate-work-split)
- [Summary](#summary)

## Executive Summary

Today, `ghaf-infra` hardware testing assumes one downloadable image file and
flashes it with inline Jenkins logic using raw `dd`.

That does not match the direction of `tiiuae/ghaf` PR #1787, where Orin moves
toward multi-artifact flashing with Ghaf-side helper tooling.

The recommended direction is [Option C](#option-c-delegate-flashing-to-ghaf-provided-tooling):

- move target-specific flashing logic out of Jenkins Groovy
  (see [Current Jenkins Flashing Flow](#current-jenkins-flashing-flow))
- have Ghaf provide a stable flashing contract
  (see [What Ghaf Needs To Provide Next](#what-ghaf-needs-to-provide-next))
- have `ghaf-infra` orchestrate verification, device routing, and delegated
  flasher execution
  (see [What `ghaf-infra` Needs To Change](#what-ghaf-infra-needs-to-change))

We do not need to wait for PR #1787 to start. Ghaf already has relevant prior
art:

- Orin `*-flash-script` outputs in the flake
- the packaged `flash-script` image writer
- the `.github/skills/ghaf-hw-test` local flash-and-test loop

See [What Ghaf Already Provides Today](#what-ghaf-already-provides-today).

The best first step is to prototype delegated flashing on one current
single-image target such as Lenovo X1, then extend the same contract to Orin
(see [Suggested Phased Rollout](#suggested-phased-rollout)).

## Scope

This document is based on the current state of:

- `hosts/hetzci/pipelines/ghaf-hw-test.groovy`
- `hosts/hetzci/pipelines/ghaf-hw-test-manual.groovy`
- `hosts/hetzci/pipelines/modules/utils.groovy`
- `hosts/testagent/agent.nix`
- `hosts/testagent/agents-common.nix`
- `.github/skills/ghaf-hw-test/`
- the discussion and diff of `tiiuae/ghaf` PR #1787

This is a code-reading document. It does not claim that all cases have been
validated on hardware.

## Current Jenkins Flashing Flow

### 1. Build pipeline selects exactly one image artifact

`hosts/hetzci/pipelines/modules/utils.groovy` builds each target and then
searches the output directory for a single file matching:

- `*.img`
- `*.raw`
- `*.zst`
- `*.iso`

The first match returned by:

```groovy
find -L ${output}/nix -regex '.*\.\(img\|raw\|zst\|iso\)$' -print -quit
```

is stored in `manifest.image`.

This means the build side currently assumes:

- one main downloadable image per target
- one main signature file per target image
- one `IMG_URL` passed downstream into hardware testing

There is no representation in the manifest or trigger parameters for a target
that needs multiple image artifacts to be flashed together.

### 2. Hardware test job downloads one URL and turns it into one local file

`hosts/hetzci/pipelines/ghaf-hw-test.groovy` and
`hosts/hetzci/pipelines/ghaf-hw-test-manual.groovy` both take a single
`IMG_URL` parameter.

Both jobs then:

1. download that URL with `wget`
2. if the filename ends in `.zst`, decompress it
3. store the result in `env.IMG_PATH`

Only `ghaf-hw-test.groovy` additionally:

1. downloads exactly one signature file for that same artifact
2. verifies the image signature
3. verifies provenance separately

At the end of `Image download`, Jenkins has exactly one path to flash.

### 3. The flash stage writes the image directly with `dd`

Both hardware-test pipelines contain an explicit
[TODO](https://github.com/tiiuae/ghaf-infra/blob/ad53845f2f80606b5553efbe9e28a52cfc9f09ce/hosts/hetzci/pipelines/ghaf-hw-test.groovy#L289-L290):

> We should use ghaf flashing scripts or installers.
> We don't want to maintain these flashing details here.

Despite that TODO, the current behavior is still implemented in the pipeline
itself.

The flash stage:

1. switches the external target disk to the test agent through Acroname or
   `usbsdmux`
2. resolves the block-device symlink from `test_config.json`
3. optionally wipes the first and last 10 MiB for Lenovo X1 images
4. writes the image with plain `dd if=${env.IMG_PATH} of=${dev}`
5. disconnects the external disk again

Important characteristics of the current implementation:

- Jenkins does not call Ghaf's packaged `flash-script`
- Jenkins does not call `ghafdd.sh`
- Jenkins does not call `makediskimage.sh`
- Jenkins does not understand a multi-file flashing protocol
- Jenkins expects a single block-image artifact that can be streamed directly
  to the target drive

### 4. Test agents do not currently provide the new Ghaf flash helpers

The test-agent service environment includes:

- `policy-checker`
- `verify-signature`
- `ghaf-robot`
- `AcronameHubCLI`
- `usbsdmux`
- standard shell/network tooling

The agent definitions do not currently install Ghaf's new helper scripts from
PR #1787. The existing pipeline also does not try to fetch or run them from a
Ghaf checkout.

## What Ghaf Already Provides Today

Before PR #1787, the Ghaf repository already exposed flasher-related outputs
from the same revision as the target build.

### 1. Orin targets already have target-coupled `*-flash-script` outputs

`targets/nvidia-jetson-orin/flake-module.nix` exports:

- `packages.<system>.<target>` as `config.system.build.ghafImage`
- `packages.x86_64-linux.<target>-flash-script` from
  `t.hostConfiguration.pkgs.nvidia-jetpack.legacyFlashScript`
- `packages.x86_64-linux.<target>-flash-qspi` from the same target
  configuration with `onlyQSPI = true`

This means the current Ghaf repo already has a notion of:

- image output for a target
- matching target-specific flasher output
- both derived from the same Ghaf revision and target configuration

For Orin specifically, this is already stronger than a generic standalone
script living outside the build graph.

### 2. Ghaf also provides a generic packaged USB image writer

The Ghaf package overlay exports `pkgs.flash-script`, backed by
`packages/pkgs-by-name/flash-script/flash.sh`.

This script is also versioned with the Ghaf repo revision. It is still a
generic image writer rather than a target-coupled flashing contract, but it
already does more than a bare `dd` wrapper:

- accepts `.zst`, `.img`, and `.iso`
- performs `.zst` decompression itself
- validates device paths
- wipes the target disk before writing
- supports progress reporting

So while it is not yet the delegated flashing contract we want, it already
covers much of the single-image behavior that Jenkins currently reimplements
inline.

### 3. The `ghaf-hw-test` skill is relevant prior art

Ghaf also contains `.github/skills/ghaf-hw-test/`, which already implements a
local flash-and-test loop with device profiles and delegated flash behavior.
The points below are based on the skill's checked-in `config.yaml` and
`ghaf-hw-test` wrapper at the time of writing.

Relevant pieces:

- `.github/skills/ghaf-hw-test/config.yaml` defines per-device flash methods
  and target mappings
- x86 targets such as `darter-pro`, `Lenovo-X1`, `dell-7330`, and `NUC` use
  `flash_method: ghaf-flash`
- Orin targets `Orin-AGX` and `Orin-NX` use `flash_method: flash-script` and
  define `flash_script_target`
- `.github/skills/ghaf-hw-test/ghaf-hw-test` selects the flash path based on
  the device profile and dispatches to either `ghaf-flash` or the Orin flash
  script flow

This matters for Option C because it shows that Ghaf already has an existing
consumer-facing abstraction for delegated flashing, even if it currently
targets local operator workflows rather than Jenkins integration.

This skill should be treated as prior art when designing:

- a unified `ghaf-flash` entrypoint
- device profile metadata
- target-to-flasher mapping
- CLI argument shape for delegated flashing

### 4. What is still missing for Jenkins use

Even though Ghaf already provides same-revision flasher outputs and the
`ghaf-hw-test` skill provides local delegated flash behavior, Ghaf does not
yet provide a single Jenkins-ready contract that `ghaf-infra` can consume
uniformly across targets.

Missing pieces include:

- machine-readable declaration of which flasher belongs to which artifact set
- a manifest describing required flash inputs
- a stable handoff format for hardware-test jobs
- a generalized approach covering both single-image and multi-artifact targets
- current-main equivalents of the PR #1787 helper scripts

So the statement "the flasher lives in the same Ghaf revision as the image
artifacts" is already true for Orin `*-flash-script` outputs and for the
generic `flash-script`, and Ghaf already has local delegated flashing prior art
via `.github/skills/ghaf-hw-test/`. It is still only partially true as a
complete CI integration story.

## What PR #1787 Changes in Ghaf

The PR changes Orin handling in two important ways.

### 1. The default Orin output changes from one disk image to two images

The old Orin path produced a disk image suitable for direct writing to a block
device.

The new path builds:

- `esp.img.zst`
- `root.img.zst`

under `system.build.ghafFlashImages`, and wires `system.build.ghafImage` to
that output directory.

This breaks the current Jenkins assumption that a target has one main image
artifact.

### 2. The PR introduces helper scripts to reassemble and flash those images

The PR adds:

- `packages/pkgs-by-name/makediskimage-script/makediskimage.sh`
- `packages/pkgs-by-name/ghafdd-script/ghafdd.sh`

The intended model described in the PR discussion is:

- `makediskimage.sh` merges `esp.img.zst` and `root.img.zst` into a single
  disk image
- `ghafdd.sh` is a convenience wrapper that auto-detects those split images
  and runs the merger when needed
- the user should ideally not have to think about the two-image shape

That intent is compatible with the Jenkins pipeline only if Jenkins starts
calling one of those helpers, or if Ghaf again publishes one single ready-to-
flash artifact for hw testing.

## Findings From The PR Review

The items below summarize the findings gathered so far while comparing PR #1787
to the current `ghaf-infra` flashing design.

### Finding 1: Jenkins hardware testing is currently incompatible with split Orin images

This is the clearest result.

`ghaf-infra` hardware testing:

- receives one `IMG_URL`
- verifies one image signature
- decompresses one file
- writes one file to the target device

PR #1787 changes Orin builds to produce two images by default.

Without additional changes, the Jenkins flow cannot correctly flash Orin
artifacts produced by the PR.

The PR discussion already noticed this. A reviewer explicitly stated that the
Devenv team would need to update the test pipeline flash stage before the PR
could be merged.

### Finding 2: The PR author intends helper scripts to hide the split-image detail, but Jenkins does not use them

The PR comments explain that:

- `makediskimage.sh` is the "real" merger
- `ghafdd.sh` is intended to hide that complexity from users
- the "original Ghaf flasher script" can then write the merged image to USB

That clarifies intended user workflow, but it does not solve the Jenkins case.

At the moment Jenkins:

- does not build the merged disk image
- does not run `ghafdd.sh`
- does not run `makediskimage.sh`
- does not install those tools on the test agent as part of the current
  pipeline path

So the user-facing abstraction described in the PR comments does not yet exist
inside `ghaf-infra` automation.

Related nuance:

- Ghaf already exports same-revision Orin flash-script outputs today
- Jenkins does not consume those outputs either

So the integration gap is not only about the new helper scripts from PR #1787.
It is also that `ghaf-infra` currently ignores Ghaf-provided flasher outputs in
general and only consumes the image artifact.

### Finding 3: The split-image path had already shown boot problems during PR discussion

In the PR discussion, a tester reported that:

- the direct `-flash-script` path booted fine
- the merged `esp.img.zst` + `root.img.zst` path booted, but VMs failed to
  start

The author later replied that the issue was related to the root image not
containing the required NixOS closure linkage and that symbolic links would be
created during merge.

This matters to `ghaf-infra` because it means:

- the split-image path was not only an artifact-shape change
- it also had bootability issues while being developed
- those fixes lived in the merge script, not in the Jenkins pipeline

This strengthens the case that Jenkins must not simply pick one of the new
files and `dd` it to disk.

### Finding 4: Full disk resize was still an open problem in the PR discussion

The PR author explicitly said that all steps were working except full disk
resize and later added `orin.nix` changes intended to enable repartitioning
and filesystem growth.

This has two implications for `ghaf-infra`:

- the PR was still stabilizing behavior after initial review comments
- even if the artifact-shape mismatch is solved, the booted system behavior on
  larger target media must still be validated by hardware tests

### Finding 5: Helper-script integration is still rough even for manual local use

The PR discussion includes a report that `ghafdd.sh` failed when run from the
root of the Ghaf repository because it could not find `makediskimage.sh`.

That means even the intended manual convenience path was still being fixed
during the PR.

For Jenkins integration, this suggests:

- script location assumptions should not be replicated blindly
- a stable invocation contract is needed
- artifact inputs should be explicit rather than inferred from working
  directory layout

## Detailed Pipeline Constraints

These are the practical constraints any `ghaf-infra` fix will need to respect.

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

This existing manifest is important prior art for Option C. A future flash
manifest does not need to start from zero; it can build on the current
artifact/signing metadata model and extend it with flash semantics.

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
pipeline starts consuming true multi-artifact flash inputs.

### Test agent execution model

The pipeline currently performs the flashing logic inline in Jenkins Groovy and
shell.

Possible integration directions:

- move the logic into a script shipped by `ghaf-infra`
- call a Ghaf-provided flasher script from a checked-out Ghaf tree
- install the needed Ghaf flasher package on test agents

Whichever route is chosen, the contract must be stable enough for:

- prod/dev/release Jenkins
- different target families
- existing non-Orin single-image targets

## Likely Directions For Follow-Up Work

Based on current findings, the most plausible approaches are:

### Option A: Preserve a single ready-to-flash artifact for Jenkins

Pros:

- smallest change in `ghaf-infra`
- keeps existing `IMG_URL` contract
- keeps existing signature and `dd` flow mostly intact

Cons:

- Ghaf would need to continue publishing or generating a merged disk image for
  hardware testing
- may duplicate work if the new split-image model is the desired long-term
  format

### Option B: Teach Jenkins/test agents to handle split images

Pros:

- aligns directly with the new Orin artifact model
- keeps artifact semantics explicit

Cons:

- requires pipeline API changes
- requires new signature-handling decisions
- introduces more target-specific flashing logic into `ghaf-infra`, which the
  current TODO already says should be avoided

### Option C: Delegate flashing to Ghaf-provided tooling

Pros:

- matches the [TODO already present](https://github.com/tiiuae/ghaf-infra/blob/ad53845f2f80606b5553efbe9e28a52cfc9f09ce/hosts/hetzci/pipelines/ghaf-hw-test.groovy#L289-L290) in the pipeline
- reduces duplicated flashing logic in Jenkins Groovy
- lets Ghaf own target-specific flash behavior

Cons:

- needs a robust interface between `ghaf-infra` and Ghaf tooling
- artifact discovery and parameter passing still need to be designed
- current Ghaf flasher outputs are not yet exposed through a single CI-facing
  manifest/contract

Preferred variant of Option C:

- use a flasher produced from the same Ghaf revision as the target image
- transfer that exact flasher to the test agent during the job
- avoid separately pinned or preinstalled flasher logic on the test agent

This avoids drift between:

- image layout
- flashing logic
- target-specific behavior
- helper-script expectations

## Recommended Immediate Next Steps

Before changing pipeline code, the following should be answered explicitly:

1. What is the canonical flash artifact for Orin in CI: one merged disk image,
   or two independent images?
2. Which artifact(s) are signed and verified by the test pipeline?
3. Should `ghaf-infra` call Ghaf's flasher tooling, or should it continue to
   own the flashing steps?
4. If Ghaf tooling is used, how will that tooling be delivered to test agents:
   transferred at runtime from the same Ghaf build, fetched artifact, or
   checked-out repository path?
5. Do we want a cross-target abstraction that also replaces the current raw
   `dd` path for laptops and other boards?

Based on current findings, runtime transfer from the same Ghaf build is likely
better than separately pinning a flasher in the test-agent configuration.

## Expanding Option C

This section turns Option C into a more concrete implementation plan.

The core idea is:

- Ghaf owns target-specific flashing behavior
- `ghaf-infra` owns Jenkins orchestration, verification, and device routing
- the flasher used in hardware testing comes from the same Ghaf build as the
  image artifacts under test

### What Ghaf Needs To Provide Next

The next step in Ghaf should not be "more helper scripts" by itself. Ghaf needs
to provide a stable CI-facing flashing contract.

#### 1. A single supported flashing entrypoint

Ghaf should expose one supported flashing entrypoint that `ghaf-infra` can call
without knowing target-specific implementation details.

This can be:

- one universal app such as `ghaf-flash`
- or one target-specific flasher output plus a shared manifest contract

The important part is not the exact name. The important part is that Jenkins
can invoke it in a consistent way.

Minimum requirements for the entrypoint:

- does not depend on current working directory
- accepts explicit input paths or artifact directory
- supports existing single-image targets
- supports future split-image targets
- exits nonzero on incomplete or inconsistent inputs
- is safe to invoke non-interactively in CI

#### 2. A machine-readable flash manifest

Ghaf should emit a manifest describing how a target is meant to be flashed.

That manifest should be produced from the same target configuration and same
revision as the build artifacts.

At minimum, the manifest should answer:

- which flasher should be used
- which artifact files are required for flashing
- whether the target is single-image or multi-artifact
- whether the artifacts need preprocessing or merging
- what the expected output medium is

Illustrative fields:

```json
{
  "formatVersion": 1,
  "target": "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug",
  "flash": {
    "mode": "single-image",
    "flasher": "ghaf-flash",
    "artifacts": [
      { "role": "disk-image", "path": "ghaf-lenovo-x1-carbon-gen11-debug.img.zst" }
    ]
  }
}
```

Or for a split-image target:

```json
{
  "formatVersion": 1,
  "target": "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
  "flash": {
    "mode": "multi-artifact",
    "flasher": "ghaf-flash",
    "artifacts": [
      { "role": "esp", "path": "esp.img.zst" },
      { "role": "root", "path": "root.img.zst" }
    ]
  }
}
```

The exact schema can vary, but `ghaf-infra` needs this information explicitly.

#### 3. A derivation or app for the flasher itself

The flasher should be available as a real Nix output, not just as a script in
the source tree.

That could be:

- `packages.<system>.ghaf-flash`
- `apps.<system>.ghaf-flash`
- target-specific flash package outputs

The current Orin `*-flash-script` outputs show that Ghaf already has pieces of
this model. The next step is to make that consumable in a generic CI flow.

#### 4. Clear artifact roles

Today `ghaf-infra` discovers images by filename pattern. That is too weak.

Ghaf should explicitly distinguish:

- flashable disk image
- installer ISO
- firmware flasher
- flash manifest
- provenance
- image signatures

This matters even before split-image targets, because it gives Jenkins a better
contract than "first matching `*.img|*.zst|*.iso` wins".

#### 5. Backward-compatible support for current single-image targets

To start Option C before PR #1787 lands, Ghaf should support the same manifest
and flasher entrypoint for existing single-image targets.

That allows `ghaf-infra` to adopt the new interface without waiting for Orin.

### What `ghaf-infra` Needs To Change

`ghaf-infra` does not need to learn target-specific flashing internals. It does
need to stop assuming that the build output is only one image file.

#### 1. Extend the build-to-test handoff

Instead of passing only:

- `IMG_URL`

the build pipeline should eventually pass enough information for the hardware
test job to reconstruct the flashing contract.

This can be done in stages:

- first add `FLASH_MANIFEST_URL`
- later reduce direct dependence on `IMG_URL`

The downstream hardware-test job should consume the manifest rather than infer
flash behavior from filename patterns.

#### 2. Keep verification in Jenkins

`ghaf-infra` should probably continue to own:

- artifact download
- provenance verification
- signature verification

That keeps policy enforcement centralized in Jenkins and test-agent
configuration.

The flasher then consumes already-downloaded, already-verified local inputs.

#### 3. Transfer the Ghaf flasher at runtime

Preferred model:

- build pipeline produces image artifacts and flasher from the same Ghaf build
- hardware-test job downloads artifacts and resolves the flasher store path
- Jenkins copies the flasher closure to the test agent at runtime
- test agent invokes that exact flasher for the target under test

This avoids drift between:

- target artifacts
- target layout expectations
- target-specific flashing logic

#### 4. Replace inline `dd` with delegated invocation

The current pipeline should keep:

- Acroname or `usbsdmux` device switching
- target disk path resolution
- error reporting around mount/unmount visibility

But the actual flashing step should become something like:

```bash
ghaf-flash \
  --manifest "$FLASH_MANIFEST" \
  --artifact-dir "$ARTIFACT_DIR" \
  --device "$TARGET_DEVICE"
```

That removes target-specific image handling from Groovy while preserving
controller-side orchestration.

#### 5. Keep a transitional compatibility mode

During rollout, `ghaf-infra` should support both:

- legacy single `IMG_URL` flashing
- manifest-driven delegated flashing

That reduces risk while the new Ghaf interface is still settling.

### Can We Start Before PR #1787 Lands?

Yes. In fact, we probably should.

Starting with existing single-image targets is the safest way to exercise the
interface before adding Orin-specific complexity.

The best early candidates are:

- Lenovo X1
- Dell Latitude
- System76

Reasons:

- current Jenkins flow already flashes them as one disk image
- no split-image handling is needed yet
- we can validate the orchestration model separately from Orin's artifact
  format changes

### Suggested Phased Rollout

#### Phase 1: Define the contract on a single-image target

In Ghaf:

- add a flash manifest for one existing single-image target
- expose a CI-consumable flasher package/app for that target
- make sure the flasher can consume explicit file paths

In `ghaf-infra`:

- add support for `FLASH_MANIFEST_URL`
- download the manifest in `ghaf-hw-test`
- keep existing `dd` path as fallback
- add one optional delegated-flash path behind a switch

Target for first validation:

- `lenovo-x1-carbon-gen11-debug`

This would prove:

- build-to-test manifest handoff
- runtime flasher transfer
- delegated flasher execution on test agent
- no regression in current signature/provenance verification

#### Phase 2: Generalize for other current single-image targets

After one target works:

- extend the same pattern to Dell and System76
- remove target-specific assumptions from the delegated path
- keep legacy fallback until confidence is high

This phase should answer whether the delegated flashing interface is generic
enough for non-Orin hardware.

#### Phase 3: Add Orin split-image support

Only after the delegated model works for single-image targets:

- connect the same contract to Orin
- teach the Ghaf flasher to consume split-image manifests
- validate hardware boot and resize behavior

At this point, `ghaf-infra` should not need Orin-specific flash logic in
Groovy. It should only need:

- download
- verify
- connect disk
- call flasher

#### Phase 4: Retire inline flashing logic

After the delegated path is proven:

- remove the inline `dd`-based flashing logic from
  `ghaf-hw-test.groovy`
- remove the same logic from
  `ghaf-hw-test-manual.groovy`
- simplify image-discovery assumptions in `utils.groovy`

### Proposed Immediate Work Split

#### Ghaf-side immediate work

1. Decide whether the preferred delegated interface is:
   - one universal `ghaf-flash`
   - or target-specific flasher outputs plus manifest metadata
2. Define a minimal flash manifest schema
3. Implement that schema for one existing single-image target
4. Ensure the flasher can be built and copied as a Nix output
5. Make artifact paths explicit in the manifest

#### `ghaf-infra` immediate work

1. Add document-level agreement on the delegated flashing model
2. Extend pipeline metadata to carry a manifest URL or equivalent
3. Add a new code path in `ghaf-hw-test` that:
   - downloads the manifest
   - downloads all declared artifacts
   - transfers the declared flasher to the test agent
   - invokes the flasher on the chosen device
4. Keep legacy `dd` fallback for all targets during early rollout
5. Validate the path on one laptop target first

### Main Recommendation

Option C should begin with non-Orin targets.

That lets us test the hard parts that actually belong to `ghaf-infra`:

- build/test handoff shape
- manifest plumbing
- runtime transfer of Ghaf-provided flasher outputs
- delegated flashing on test agents

before we add the Orin-specific complexity introduced by PR #1787.

## Summary

Today, Jenkins hardware testing in `ghaf-infra` is built around one flashable
image file and a direct `dd` write to the target drive.

PR #1787 in `ghaf` changes Orin to a split-image model and introduces helper
scripts intended to reconstruct or abstract that detail away. The current
`ghaf-infra` pipeline does not use those helpers and cannot correctly consume
the new artifact shape as-is.

At the same time, Ghaf already exposes same-revision flasher outputs for Orin
targets. This suggests that the long-term fix should not be to duplicate more
target-specific flashing logic in Jenkins, but to define a clean interface for
passing Ghaf-provided flashing logic and artifacts into the hw-test pipeline.

The main conclusion so far is simple:

- current Jenkins hw flashing is single-image oriented
- PR #1787 makes Orin multi-artifact by default
- Ghaf already has some same-revision flasher outputs, but `ghaf-infra` does
  not consume them
- integration work is required in either `ghaf`, `ghaf-infra`, or both before
  that change can be safely used in Jenkins hardware testing
