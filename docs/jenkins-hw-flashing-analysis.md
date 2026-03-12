<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Jenkins Hardware Flashing Analysis

This document is a companion to
[Jenkins Hardware Flashing Notes](jenkins-hw-flashing-notes.md), which is
authoritative for current operational status and active design constraints.

This document captures the investigative background gathered while reviewing
[`tiiuae/ghaf` PR#1787](https://github.com/tiiuae/ghaf/pull/1787),
"NVidia AGX: 2 stage initrd install", including the current pipeline
walkthrough, impact analysis, integration-path comparison, and the detailed
[Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling) expansion plan.

## Table of Contents

- [Scope](#scope)
- [Current Jenkins Flashing Flow](#current-jenkins-flashing-flow)
- [What Ghaf Already Provides Today](#what-ghaf-already-provides-today)
- [What PR#1787 Changes in Ghaf](#what-pr-1787-changes-in-ghaf)
- [Why Orin Moved From One Image to Two](#why-orin-moved-from-one-image-to-two)
- [Findings From The PR Review](#findings-from-the-pr-review)
- [Likely Directions For Follow-Up Work](#likely-directions-for-follow-up-work)
- [Recommended Immediate Next Steps](#recommended-immediate-next-steps)
- [Multi-Artifact Signing Options](#multi-artifact-signing-options)
- [Expanding Path A](#expanding-path-a)
  - [What Ghaf Needs To Provide Next](#what-ghaf-needs-to-provide-next)
  - [What ghaf-infra Needs To Change](#what-ghaf-infra-needs-to-change)
  - [Can We Start Before PR#1787 Lands?](#can-we-start-before-pr-1787-lands)
  - [Suggested Phased Rollout](#suggested-phased-rollout)
  - [Proposed Immediate Work Split](#proposed-immediate-work-split)
  - [Main Recommendation](#main-recommendation)
- [Primary Sources](#primary-sources)
- [Summary](#summary)

## Scope

This document is based on the current state of:

- `hosts/hetzci/pipelines/ghaf-hw-test.groovy`
- `hosts/hetzci/pipelines/ghaf-hw-test-manual.groovy`
- `hosts/hetzci/pipelines/modules/utils.groovy`
- `hosts/testagent/agent.nix`
- `hosts/testagent/agents-common.nix`
- `.github/skills/ghaf-hw-test/`
- the discussion and diff of `tiiuae/ghaf`
  [PR#1787](https://github.com/tiiuae/ghaf/pull/1787)

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
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787). The existing pipeline
also does not try to fetch or run them from a Ghaf checkout.

## What Ghaf Already Provides Today

Before [PR#1787](https://github.com/tiiuae/ghaf/pull/1787), the Ghaf
repository already exposed flasher-related outputs from the same revision as the
target build.

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

This matters for [Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling)
because it shows that Ghaf already has an existing
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
- current-main equivalents of the
  [PR#1787](https://github.com/tiiuae/ghaf/pull/1787) helper scripts

So the statement "the flasher lives in the same Ghaf revision as the image
artifacts" is already true for Orin `*-flash-script` outputs and for the
generic `flash-script`, and Ghaf already has local delegated flashing prior art
via `.github/skills/ghaf-hw-test/`. It is still only partially true as a
complete CI integration story.

<a id="what-pr-1787-changes-in-ghaf"></a>
## What PR#1787 Changes in Ghaf

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

## Why Orin Moved From One Image to Two

From the `ghaf-infra` Jenkins viewpoint, the important root cause is that Orin
is moving from a **whole-disk image contract** to a
**partition-payload contract**.

Before [PR#1787](https://github.com/tiiuae/ghaf/pull/1787), Orin used
`sdimage.nix` and exported one disk image through `system.build.sdImage`. That
image already contained the GPT layout, the ESP, and the root partition
contents, so Jenkins could treat it like any other single artifact and write it
directly to a block device with `dd`.

[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) changes the default Orin
output to `system.build.ghafFlashImages`, which contains:

- `esp.img.zst`
- `root.img.zst`

This is not just a packaging change. It follows the model used by NVIDIA's
`l4t_initrd_flash.sh` flow: the flashing logic owns partition creation and
device-specific layout, while the build side provides the payloads for the
individual partitions. In the PR implementation:

- `esp.img.zst` is a standalone FAT32 ESP containing the UEFI boot content
- `root.img.zst` is a standalone ext4 root filesystem image
- the target disk layout is recreated later by Ghaf helper tooling such as
  `makediskimage.sh` or by the initrd flashing logic itself

So the reason there are now two files is that Orin is no longer published as a
preassembled flashable disk image by default. It is published as the two
partition images that the initrd-flash path expects.

There is also a hardware and vendor-tooling reason for this change, not just a
Ghaf packaging refactor.

For the NVIDIA reference configurations documented in Jetson Linux, Orin NX and
Orin Nano are flashed as **QSPI-NOR plus external storage**:

- QSPI-NOR carries the early boot firmware
- USB, NVMe, or microSD carries the OS storage, depending on the module and
  carrier-board combination

This is a real storage split, not just a software packaging choice. On these
NX/Nano reference paths there is no eMMC-backed internal rootfs flow analogous
to AGX Orin's documented "QSPI-NOR and eMMC" path. NVIDIA's own Quick Start
tables reflect that distinction directly.

That hardware split also maps onto the boot chain. BootROM loads the early boot
components, MB1 loads MB2, and MB2 hands off to UEFI. On the NX/Nano reference
paths, those bootloader stages are tied to the QSPI-resident boot firmware,
while UEFI then boots the OS payloads from the ESP on external storage. From a
flashing perspective, that means QSPI firmware and OS partitions are separate
concerns because they live on different media and are handled by different
stages of the boot chain.

NVIDIA documents that the external-storage NX/Nano path is only supported
through `l4t_initrd_flash.sh`. NVIDIA also states that for Orin NX and Nano,
initrd flashing is the official method and that production systems must use it
because the memory layout produced by `flash.sh` differs from the initrd-flash
layout and is not suitable for OTA.

That matters because `l4t_initrd_flash.sh` is naturally partition-oriented: it
creates or applies the target storage layout and writes partition payloads,
Rather than assuming one prebuilt whole-disk image, Ghaf
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) is effectively adapting
Orin output to that vendor contract.

Security is the other driver. NVIDIA's Secure Boot guidance for Orin external
storage flows uses `l4t_initrd_flash.sh --uefi-keys ...` together with the
external NVMe partition XML and QSPI layout. NVIDIA's documented one-step
secure-flash commands use `flash.sh --uefi-keys` for AGX/internal-storage
targets and `l4t_initrd_flash.sh --uefi-keys` for Orin NX/Nano external-storage
targets.

From that command split, plus the
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) rationale, the working
`ghaf-infra` constraint is: the old `flash.sh` path is not the secure
external-storage signing flow Ghaf needs for NX/Nano systems rooted on NVMe/USB
media. That is the practical forcing function behind the switch away from the
old single-image publishing model.

This matters to `ghaf-infra` because the current Jenkins integration is still
built around the older contract:

- one discovered image artifact
- one image signature
- one `IMG_URL`
- one local file passed to the flash step

That contract matched `sdImage`. It does not match the new Orin
partition-payload output.

## Findings From The PR Review

The items below summarize the findings gathered so far while comparing
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) to the current
`ghaf-infra` flashing design.

### Finding 1: Jenkins hardware testing is currently incompatible with split Orin images

This is the clearest result.

`ghaf-infra` hardware testing:

- receives one `IMG_URL`
- verifies one image signature
- decompresses one file
- writes one file to the target device

[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) changes Orin builds to
produce two images by default.

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

So the integration gap is not only about the new helper scripts from
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787). It is also that
`ghaf-infra` currently ignores Ghaf-provided flasher outputs in general and
only consumes the image artifact.

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

For the practical constraints that any implementation must respect, including
the single `IMG_URL` contract, signature and provenance handling, and the test
agent execution model, see
[Active Design Constraints](jenkins-hw-flashing-notes.md#active-design-constraints)
in the main document.

## Likely Directions For Follow-Up Work

Based on current findings, the most plausible integration paths are below.
These are a separate decision axis from `U1`-`U3` and `S1`-`S4`:
[Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling),
[Path B](#path-b-preserve-a-single-ready-to-flash-artifact-for-jenkins), and
[Path C](#path-c-teach-jenkinstest-agents-to-handle-split-images) describe
where flashing behavior lives in the Jenkins-to-Ghaf integration, while `U*`
and `S*` describe how signing works once the artifact model is chosen.

### Path A: Delegate flashing to Ghaf-provided tooling

This path assumes Jenkins uses a flasher produced from the same Ghaf revision
as the target image, transfers that exact flasher to the test agent during the
job, and avoids separately pinned or preinstalled flasher logic. That avoids
drift between image layout, flashing logic, target-specific behavior, and
helper-script expectations.

Pros:

- reduces duplicated flashing logic in Jenkins Groovy
- lets Ghaf own target-specific flash behavior and the maintenance burden that
  comes with it
- matches the [TODO already present](https://github.com/tiiuae/ghaf-infra/blob/ad53845f2f80606b5553efbe9e28a52cfc9f09ce/hosts/hetzci/pipelines/ghaf-hw-test.groovy#L289-L290) in the pipeline

Cons:

- needs a robust interface between `ghaf-infra` and Ghaf tooling
- artifact discovery and parameter passing still need to be designed
- current Ghaf flasher outputs are not yet exposed through a single CI-facing
  manifest/contract

### Path B: Preserve a single ready-to-flash artifact for Jenkins

Pros:

- smallest change in `ghaf-infra`
- keeps existing `IMG_URL` contract
- keeps existing signature and `dd` flow mostly intact

Cons:

- Ghaf would need to continue publishing or generating a merged disk image for
  hardware testing
- may duplicate work if the new split-image model is the desired long-term
  format

### Path C: Teach Jenkins/test agents to handle split images

Pros:

- aligns directly with the new Orin artifact model
- keeps artifact semantics explicit

Cons:

- requires pipeline API changes
- requires new signature-handling decisions
- introduces more target-specific flashing logic and maintenance burden into
  `ghaf-infra`, even though that behavior should live in Ghaf rather than be
  implemented in Jenkins Groovy

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

Historical note: the validated prototype described in
[Jenkins Hardware Flashing Notes](jenkins-hw-flashing-notes.md) has since
answered part of this for single-image targets by transferring the Ghaf flasher
closure directly via Nix. The unresolved parts now mainly concern the future
multi-artifact Orin path.

## Multi-Artifact Signing Options

The current pipeline performs three distinct signing operations in order: SLSA
provenance signing (per-build, covers `provenance.json`), optional UEFI image
signing, and SLSA image signing (covers the final image artifact). See
[Signature and provenance handling](jenkins-hw-flashing-notes.md#signature-and-provenance-handling)
for the full description of today's model.

SLSA provenance signing is a per-build attestation (`utils.groovy:150,196`).
It is not image-specific and is unaffected by the artifact shape: one
provenance attestation per build regardless of whether the build produces one
image or several. The options below address only the SLSA **image-artifact**
signature step and the UEFI signing step.

Based on the current
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) artifact shape, the
options do not look equally strong. The preferred order below reflects the
current understanding from the PR diff, the Jenkins prototype work, and the
NVIDIA flashing model.

Recommended UEFI signing order:

| UEFI Option | Status | Why |
|---|---|---|
| `U1` sign ESP directly | Preferred | Matches the native artifact model: `esp.img.zst` already contains the EFI payloads |
| `U2` sign before splitting | Viable but unnatural | Not supported by the current PR shape; would need an extra compatibility stage |
| `U3` defer until after merge | Not recommended | Operationally expensive and breaks today's trust ordering |

Recommended SLSA signing order:

| SLSA Option | Status | Why |
|---|---|---|
| `S1` signed manifest | Preferred long-term | Best fit for delegated flashing and any future multi-artifact target |
| `S2` per-artifact signatures | Viable | Simple, direct, split-artifact-native model |
| `S3` build-time merge | Compatibility bridge | Useful for today's Jenkins contract and `ghafdd.sh`, but weaker as the native end-state |
| `S4` bundle archive | Viable but weaker | Preserves single download but hides artifact roles and adds repackaging |

Taken together, the current recommendation is:

- long-term native direction: `U1` + `S1`
- simpler split-artifact variant: `U1` + `S2`
- transitional Jenkins-compatible bridge: `S3`

### S1: Signed flash manifest with per-artifact checksums

The build produces a flash manifest listing all artifacts with sha256
checksums. SLSA image-sign only the manifest: one signature covers the whole
artifact set. Verification: check manifest signature, then verify each
downloaded artifact against its manifest checksum.

Pros:

- single signature verification step
- naturally extensible to any number of artifacts
- fits the flash manifest design from
  [Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling)
- models artifact roles explicitly instead of hiding them behind a repackaged blob

Cons:

- indirect trust chain (signature → manifest → checksums → artifacts)
- requires new manifest schema
- requires `ghaf-hw-test` to understand manifest-driven downloads

### S2: Per-artifact SLSA image signatures

Each flash artifact gets its own `.sig` (`esp.img.zst.sig`,
`root.img.zst.sig`). Verification: `ghaf-hw-test` downloads and verifies each
artifact+sig pair.

Pros:

- each artifact independently verifiable
- aligns directly with the split-image model produced by
  [PR#1787](https://github.com/tiiuae/ghaf/pull/1787)
- no need to invent an extra wrapper artifact

Cons:

- multiple verification steps
- pipeline API must accept multiple URLs
- `verify-signature image` would need to run once per artifact

### S3: Build-time merge (sign a single merged image)

The build pipeline merges split images into one disk image (via
`makediskimage.sh`) before any signing. UEFI sign and SLSA image-sign the
merged image exactly as today. The pipeline API is unchanged (single
`IMG_URL`).

This option is weaker as the long-term native Orin model, because
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) builds `esp.img.zst` and
`root.img.zst` directly and the NVIDIA/Ghaf initrd flow is fundamentally
partition-oriented. But it remains a valid compatibility bridge for
`ghaf-infra`, because `ghafdd.sh` already merges those split images into a real
flashable disk image for today's external-disk workflow.

Pros:

- zero verification changes
- zero trust model changes
- provenance attestation unchanged
- directly compatible with the current single-`IMG_URL` Jenkins contract

Cons:

- requires merge tooling in build environment
- diverges from the native split-artifact direction
- creates a compatibility artifact rather than using the canonical
  [PR#1787](https://github.com/tiiuae/ghaf/pull/1787) outputs directly

### S4: Bundle archive (single downloadable)

Package all flash artifacts into a single archive (tarball or nar). SLSA
image-sign the archive: single artifact, single signature. Preserves
single-URL model.

Pros:

- minimal pipeline API change
- single signature

Cons:

- new archive format
- unpack overhead
- opaque until extracted
- weaker fit than a signed manifest because artifact roles remain implicit

### UEFI signing and split images

This is a cross-cutting concern that applies primarily to `S1`, `S2`, and `S4`. `S3`
sidesteps most of the timing question by merging first and then signing one
compatibility artifact.

For split images, the key fact from
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) is that `flash-images.nix`
builds `esp.img` and `root.img` as independent derivations. There is no
intermediate full-disk image that later gets split. The artifacts are born
separate.

Comparison with today's single-image flow:

- **Current single-image model**: Jenkins passes one full disk image into
  `uefisign` or `uefisign-simple` in the `Sign (UEFI)` stage
  (`utils.groovy:219-234`), the signer updates the EFI binaries inside the
  ESP, replaces the image artifact in place, and then the pipeline applies the
  SLSA image signature to that final disk image.
- **Split-image model**: the UEFI-executed content lives in the ESP artifact,
  not in `root.img.zst`. So the natural equivalent is to sign the EFI binaries
  carried by `esp.img.zst`, while `root.img.zst` remains a normal flash
  artifact but not a UEFI-signing target by itself.

This distinction is the key design point: for split images, UEFI signing is
about the ESP payload, not about applying an equivalent signature operation to
every artifact in the set.

NVIDIA's own Secure Boot model also splits the problem into two layers:

- low-level boot-chain trust starts at BootROM and authenticates boot code
  using fused PKC keys; on Orin, NVIDIA documents RSA 3K, ECDSA P-256, and
  ECDSA P-521 as the supported PKC types, and on supported platforms SBK is
  additionally used to encrypt bootloader components
- after that point, UEFI Secure Boot uses the PK/KEK/db hierarchy, where the
  db keys sign the UEFI payloads that firmware loads

From the Jenkins perspective, this is why "UEFI signing" should not be confused
with signing the whole flash set. The UEFI db keys protect the EFI payloads in
the ESP, while the lower boot-chain trust for QSPI firmware belongs to the
NVIDIA secure-flash flow.

NVIDIA's UEFI key config also makes the correspondence with today's Jenkins
signing model explicit. In `uefi_keys.conf`, NVIDIA uses
`UEFI_DB_1_KEY_FILE` and `UEFI_DB_1_CERT_FILE` as the payload-signing key and
certificate for UEFI-loaded artifacts. That is conceptually the same role that
`DB.pem` plus the HSM-backed db key plays in the current `uefisign-simple`
pipeline step.

There is no evidence in
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) that the published
`esp.img.zst` artifact is already UEFI-signed before Jenkins sees it.
`flash-images.nix` constructs the ESP with `mkfs.vfat` and `mcopy`, while the
secure-boot-related logic in `initrd-flash.nix` signs boot images and
firmware-side artifacts. So "the ESP may already be signed" remains an open
question for future Ghaf integration, not a conclusion from the PR as it
stands.

### U1: Sign the ESP partition image directly

This is the preferred native direction. It matches the actual artifact model
and keeps UEFI signing tied to the EFI payloads. It likely requires `uefisign`
or a replacement to handle a raw FAT32 ESP image instead of a full GPT disk
image.

### U2: Sign before splitting

This remains possible in principle, but it is no longer natural. Since
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) does not build a full disk
image first, this would require an extra compatibility stage to merge, sign,
and then re-expose split outputs. That makes it materially less attractive than
`U1`.

### U3: Defer UEFI signing until after merge

This is not recommended. If the delegated flasher merges on the test agent,
this would require HSM access and signing tools on test agents or an extra
controller-side round-trip. It also inverts today's trust ordering: the SLSA
image signature would cover the pre-UEFI-signed artifacts, not the final signed
image.

For `ghaf-infra`, the practical comparison is:

- in the single-image pipeline, one artifact is both the flash payload and the
  SLSA image-signing target after UEFI signing
- in a split-image pipeline, either the ESP alone must be UEFI-signed before
  publication, or a compatibility-only merged artifact must be created and
  signed explicitly for Jenkins consumption

The first shape is the better long-term fit for Orin. The second remains
useful only as a transitional bridge while Jenkins still depends on the
single-image contract.

## Expanding Path A

This section turns
[Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling) into a more
concrete implementation plan.

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

To start [Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling) before
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) lands, Ghaf should support
the same manifest and flasher entrypoint for existing single-image targets.

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

<a id="can-we-start-before-pr-1787-lands"></a>
### Can We Start Before PR#1787 Lands?

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

For current status of each phase, see
[Phased Rollout Plan](jenkins-hw-flashing-notes.md#phased-rollout-plan) in the
main document.

This phased rollout is specifically the rollout of
[Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling), not a neutral
plan covering all integration paths.

For the split-image signing choices that become relevant in
[Phase 3](#phase-3-add-orin-split-image-support), see
[Multi-Artifact Signing Options](#multi-artifact-signing-options).

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

This was the original investigative direction. The validated prototype later
simplified [Phase 1](#phase-1-define-the-contract-on-a-single-image-target) by
passing `FLASH_CACHE_URL` and `FLASH_STORE_PATH` directly, without a manifest,
because Lenovo X1 still uses a single image. A flash manifest remains the
likely direction for
[Phase 3](#phase-3-add-orin-split-image-support), where Orin needs true
multi-artifact inputs.

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

The prototype has since validated the laptop-target subset of this plan using a
cache URL plus store path instead of a manifest. The manifest-oriented version
remains the more likely endpoint once
[Phase 3](#phase-3-add-orin-split-image-support) adds split-image Orin support.

### Main Recommendation

[Path A](#path-a-delegate-flashing-to-ghaf-provided-tooling) should begin with
non-Orin targets.

That lets us test the hard parts that actually belong to `ghaf-infra`:

- build/test handoff shape
- manifest plumbing
- runtime transfer of Ghaf-provided flasher outputs
- delegated flashing on test agents

before we add the Orin-specific complexity introduced by
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787).

## Primary Sources

These are the main sources used for the
[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) analysis and for the Orin
split-image signing discussion. Keep this list as the seed set for any future
runbook or design document.

- [`tiiuae/ghaf` PR#1787, "NVidia AGX: 2 stage initrd install"](https://github.com/tiiuae/ghaf/pull/1787)
- Ghaf [PR#1787](https://github.com/tiiuae/ghaf/pull/1787) diff for
  `flash-images.nix`, `initrd-flash.nix`, `makediskimage.sh`, and `ghafdd.sh`
- [anduril/jetpack-nixos](https://github.com/anduril/jetpack-nixos)
- [NVIDIA Jetson AGX Orin Boot Flow (r35.1)](https://docs.nvidia.com/jetson/archives/r35.1/DeveloperGuide/text/AR/BootArchitecture/JetsonAgxOrinBootFlow.html)
- [NVIDIA Jetson Linux Developer Guide, Quick Start (r36.2)](https://docs.nvidia.com/jetson/archives/r36.2/DeveloperGuide/IN/QuickStart.html)
- [NVIDIA Jetson Linux Developer Guide, Flashing Support (r35.4.1)](https://docs.nvidia.com/jetson/archives/r35.4.1/DeveloperGuide/text/SD/FlashingSupport.html)
- [NVIDIA Jetson Linux Developer Guide, Flashing Support (r36.4.3)](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/FlashingSupport.html)
- [NVIDIA Jetson Linux Developer Guide, Flashing Support (r38.2)](https://docs.nvidia.com/jetson/archives/r38.2/DeveloperGuide/SD/FlashingSupport.html)
- [NVIDIA Jetson Linux Developer Guide, Partition Configuration (r36.4.3)](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/AR/BootArchitecture/PartitionConfiguration.html)
- [NVIDIA Jetson Linux Developer Guide, Update and Redundancy (r36.2)](https://docs.nvidia.com/jetson/archives/r36.2/DeveloperGuide/SD/Bootloader/UpdateAndRedundancy.html)
- [NVIDIA Jetson Linux Developer Guide, Secure Boot (r36.4.3)](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/Security/SecureBoot.html)
- [NVIDIA Jetson Linux Developer Guide, Secure Boot (r38.2)](https://docs.nvidia.com/jetson/archives/r38.2/DeveloperGuide/SD/Security/SecureBoot.html)
- [Jenkins Hardware Flashing Notes](jenkins-hw-flashing-notes.md)
- [NetHSM hardware signing notes](nethsm.md)

## Summary

Today, Jenkins hardware testing in `ghaf-infra` is built around one flashable
image file and a direct `dd` write to the target drive.

[PR#1787](https://github.com/tiiuae/ghaf/pull/1787) in `ghaf` changes Orin to
a split-image model and introduces helper scripts intended to reconstruct or
abstract that detail away. The current `ghaf-infra` pipeline does not use those
helpers and cannot correctly consume the new artifact shape as-is.

At the same time, Ghaf already exposes same-revision flasher outputs for Orin
targets. This suggests that the long-term fix should not be to duplicate more
target-specific flashing logic in Jenkins, but to define a clean interface for
passing Ghaf-provided flashing logic and artifacts into the hw-test pipeline.

For current operational status, prototype validation results, and the active
rollout plan, see
[Jenkins Hardware Flashing Notes](jenkins-hw-flashing-notes.md).
