<!--
SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Build Type: Jenkins

This is a [SLSA Provenance](https://slsa.dev/provenance/v1) `buildType` that describes the execution of a Jenkins workflow.

This build type was inspired by the Cimon Jenkins build type described [here](https://docs.cimon.build/provenance/buildtypes/jenkins/v1).

## Description

```json
"buildType": "https://github.com/tiiuae/ghaf-infra/blob/main/slsa/v1.0/L1/buildtype.md"
```

This build type describes the execution of a Jenkins workflow that builds a software artifact using nix.

## Build Definition

### External parameters

All external parameters are REQUIRED unless empty.

Parameter             | Type   | Description
--------------------- | ------ | -----------
target                | object | The target that was built
target.name           | string | The full name of the nix target
target.repository     | string | URI of the git repository (if exists)
target.ref            | string | A git reference to the commit (if exists)
workflow              | object | The workflow that was run
workflow.name         | string | The full name of the Jenkins job
workflow.repository   | string | URI of the git repository (if exists)
workflow.ref          | string | A git reference to the commit (if exists)
workflow.filePath     | string | -
job                   | object | The currently running Jenkins job
buildRun              | object | The specific build that generated the provenance

Example:

```json
"externalParameters": {
    "target": {
        "name": "#packages.x86_64-linux.generic-x86_64-debug",
        "repository": "https://github.com/tiiuae/ghaf.git",
        "ref": "c35dd3a42a412e71248b8b15a3104a037a6e8ead"
    },
    "workflow": {
        "name": "ghaf-build-pipeline.groovy",
        "repository": "https://github.com/tiiuae/ghaf-jenkins-pipeline.git",
        "ref": "dc06ce39c110c1e997f15976842c8efa55b43825"
    },
    "job": "ghaf-pipeline",
    "buildRun": "3"
}
```

### Internal parameters

All internal parameters are OPTIONAL. This build type doesn't use internal parameters.

### Resolved Dependencies

The resolvedDependencies array MUST contain all the dependencies of the target derivation, as reported by `nix-store --query --requisites`.

The dependency's URI is a hashed nix store path, which can be found on the system's nix store and binary cache.

The dependency's `digest` should contain the sha256 hash of the file contents.

The `name` and `version` fields are OPTIONAL but should be included if they are available.

Example:

```json
"resolvedDependencies": [
    {
        "uri": "/nix/store/fnndcnvnkfgw26ag2hmdj595miwq2lmx-xz-5.4.6.drv",
        "digest": {
            "sha256": "1az2bmm6713byjigzkipby4srazq3wc7y7q0nnal37x60chv49xi"
        },
        "name": "xz-5.4.6",
        "annotations": {
            "version": "5.4.6"
        }
    },
    ...
]
```

## Run Details

### Builder

The `builder.id` MUST represent the entity that generated the provenance, as per the SLSA Provenance documentation. In the case of Jenkins, this should represent the agent that ran the build. Based on this information, the provenance consumer can decide whether the build environment is secure enough to trust the produced attestation.

Example:

```json
"builder": {
    "id": "https://ghaf-jenkins-controller-prod.northeurope.cloudapp.azure.com"
}
```

### Metadata

The `invocationId` SHOULD be set to the Jenkins URL for the specific run.

Example:

```json
"metadata": {
    "invocationID": "https://ghaf-jenkins-controller-prod.northeurope.cloudapp.azure.com/job/ghaf-pipeline/1",
}
```
