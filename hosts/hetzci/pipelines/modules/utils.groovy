#!/usr/bin/env groovy

import groovy.json.JsonOutput

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout:true).trim()
}

def path_basename(String path) {
  if (path == null) {
    return null
  }
  def idx = path.lastIndexOf('/')
  return idx >= 0 ? path.substring(idx + 1) : path
}

def append_to_build_description(String text) {
  lock('build-description') {
    if(!currentBuild.description) {
      currentBuild.description = text
    } else {
      currentBuild.description = "${currentBuild.description}<br>${text}"
    }
  }
}

def create_pipeline(List<Map> targets, String testagent_host = null) {
  def pipeline = [:]
  def stamp = run_cmd('date +"%Y%m%d_%H%M%S%3N"')
  def target_commit = run_cmd('git rev-parse HEAD')
  def target_repo = run_cmd('git remote get-url origin || git remote get-url pr_origin')
  def host_name = run_cmd('hostname')
  def host_revision = run_cmd('/run/current-system/sw/bin/nixos-version --configuration-revision')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${target_commit}"
  def artifacts_local_dir = "/var/lib/jenkins/${artifacts}"
  def artifacts_href = "<a href=\"/${artifacts}\">📦 Artifacts</a>"
  def signingToken = "YubiHSM"
  def signing_possible = env.CI_ENV != 'vm' && env.CI_ENV != 'dbg'

  // Evaluate
  stage("Eval") {
    lock('evaluator') {
      sh 'nix flake show --all-systems | ansi2txt'
    }
  }
  targets.each {
    def shortname = it.target.substring(it.target.lastIndexOf('.') + 1)
    def output = "${artifacts_local_dir}/${it.target}"

    def manifest = [
      target: it.target,
      build: [
        ts_begin: null,
        ts_finished: null,
      ],
      image: null,
      uefi: [
        signed: false,
        reason: null,
        signing_key: null,
      ],
      attestations: [
        sbom: [
          csv: null,
          cdx: null,
          spdx: null,
        ],
        provenance: [
          nix_build: null,
          secureboot: null,
        ],
      ],
      signatures: [
        image: [
          path: null,
          signing_key: null,
        ],
        provenance: [
          nix_build: [
            path: null,
            signing_key: null,
          ],
          secureboot: [
            path: null,
            signing_key: null,
          ],
        ],
      ],
    ]
    if (it.no_image) {
      manifest.uefi.reason = "no_image"
    } else if (!signing_possible) {
      manifest.uefi.reason = "signing_not_possible"
    } else if (!(it.get('uefisign', false) || it.get('uefisigniso', false))) {
      manifest.uefi.reason = "not_requested"
    }

    pipeline["${it.target}"] = {
      // Build
      stage("Build ${shortname}") {
        sh "mkdir -v -p ${output}"

        manifest.build.ts_begin = run_cmd('date +%s')
        sh "nix build --fallback -v .#${it.target} --out-link ${output}/nix"
        manifest.build.ts_finished = run_cmd('date +%s')
      }
      // Provenance
      if (it.get('provenance', true)) {
        stage("Provenance ${shortname}") {
          def ext_params = """
            {
              "target": {
                "name": "${it.target}",
                "repository": "${target_repo}",
                "ref": "${target_commit}"
              },
              "workflow": {
                "name": "${host_name}",
                "repository": "https://github.com/tiiuae/ghaf-infra",
                "ref": "${host_revision}"
              },
              "job": "${env.JOB_NAME}",
              "jobParams": ${JsonOutput.toJson(params)},
              "buildRun": "${env.BUILD_ID}"
            }
          """
          withEnv([
            'PROVENANCE_BUILD_TYPE=https://github.com/tiiuae/ghaf-infra/blob/ea938e90/slsa/v1.0/L1/buildtype.md',
            "PROVENANCE_BUILDER_ID=${env.JENKINS_URL}",
            "PROVENANCE_INVOCATION_ID=${env.BUILD_URL}",
            "PROVENANCE_TIMESTAMP_BEGIN=${manifest.build.ts_begin}",
            "PROVENANCE_TIMESTAMP_FINISHED=${manifest.build.ts_finished}",
            "PROVENANCE_EXTERNAL_PARAMS=${ext_params}"
          ]) {
            sh "mkdir -v -p ${output}/attestations"
            sh """
              attempt=1; max_attempts=5;
              while ! provenance ${output}/nix --recursive --out ${output}/attestations/provenance.json; do
                echo "provenance attempt=\$attempt failed"
                if (( \$attempt >= \$max_attempts )); then
                  exit 1
                fi
                attempt=\$(( \$attempt + 1 ))
                sleep 30
              done
              echo "provenance attempt=\$attempt passed"
            """
            manifest.attestations.provenance.nix_build = "attestations/provenance.json"
          }
        }
      }
      // Build OTA pin
      if (it.get('build_otapin', false)) {
        stage("OTA Build ${shortname}") {
          def ota_target = it.target.tokenize('.').last()
          sh """
            mkdir -v -p ${ota_target}; cd ${ota_target}
            nixos-rebuild build --fallback --flake .#${ota_target}
            mv result ${artifacts_local_dir}/otapin.${ota_target}
            nix-store --add-root ${artifacts_local_dir}/otapin.${ota_target} \
              -r ${artifacts_local_dir}/otapin.${ota_target}
          """
        }
      }
      // Run sbomnix
      if (it.get('sbom', false)) {
        stage("SBOM ${shortname}") {
          def outdir = "${output}/attestations"
          sh """
            mkdir -v -p ${outdir}
            sbomnix ${output}/nix \
              --csv ${outdir}/sbom.csv \
              --cdx ${outdir}/sbom.cdx.json \
              --spdx ${outdir}/sbom.spdx.json
          """
          manifest.attestations.sbom.csv = "attestations/sbom.csv"
          manifest.attestations.sbom.cdx = "attestations/sbom.cdx.json"
          manifest.attestations.sbom.spdx = "attestations/sbom.spdx.json"
        }
      }
      // Signing stages
      // Skip signing stages in vm and dbg environments, where NetHSM is not available
      if (signing_possible && it.get('provenance', true)) {
        stage("Sign (SLSA) provenance ${shortname}") {
          lock('signing') {
            sh """
              openssl pkeyutl -sign -rawin \
                -inkey 'pkcs11:token=${signingToken};object=GhafInfraSignProv' \
                -out ${output}/attestations/provenance.json.sig \
                -in ${output}/attestations/provenance.json
            """
          }
          manifest.signatures.provenance.nix_build.path = "attestations/provenance.json.sig"
          manifest.signatures.provenance.nix_build.signing_key = "pkcs11:token=${signingToken};object=GhafInfraSignProv"
        }
      }
      if (!it.no_image) {
        stage("Find image ${shortname}") {
          def img_path = run_cmd("find -L ${output}/nix -regex '.*\\.\\(img\\|raw\\|zst\\|iso\\)\$' -print -quit")
          if (!img_path) {
            error("No image found!")
          }
          manifest.image = img_path - "${output}/"
        }
        if (signing_possible) {
          if (it.get('uefisign', false) || it.get('uefisigniso', false)) {
            stage("Sign (UEFI) ${shortname}") {
              def tmpdir = run_cmd("mktemp -d")
              def img_name = path_basename(manifest.image)

              def signer = "uefisign"
              if (it.target.contains("nvidia-jetson-orin")) {
                signer = "uefisign-simple"
              }

              lock('signing') {
                sh """
                  ${signer} /etc/jenkins/keys/secboot/DB.pem \
                    'pkcs11:token=${signingToken};object=uefi-ghaf-db' \
                    ${output}/${manifest.image} \
                    ${tmpdir}
                """
              }

              sh "mv ${tmpdir}/signed_${img_name} ${output}/${img_name}"
              // replace original image with uefisigned one
              manifest.image = img_name
              manifest.uefi.signed = true;
              manifest.uefi.reason = null
              manifest.uefi.signing_key = "pkcs11:token=${signingToken};object=uefi-ghaf-db"
            }
          }
          stage("Sign (SLSA) image ${shortname}") {
            lock('signing') {
              def img_name = path_basename(manifest.image)
              // sign the current main image be it unsigned or uefisigned
              sh """
                openssl dgst -sha256 -sign \
                  'pkcs11:token=${signingToken};object=GhafInfraSignECP256' \
                  -out ${output}/${img_name}.sig \
                  ${output}/${manifest.image}
              """
            }
            manifest.signatures.image.path = "${path_basename(manifest.image)}.sig"
            manifest.signatures.image.signing_key = "pkcs11:token=${signingToken};object=GhafInfraSignECP256"
          }
        }
      }
      // Link artifacts
      stage("Link artifacts ${shortname}") {
        if (manifest.image && !manifest.uefi.signed) {
          def img_name = path_basename(manifest.image)
          // make symlink from output root to original image if not using uefisigned
          sh "ln -s ${output}/${manifest.image} ${output}/${img_name}"
          manifest.image = img_name
        }

        writeFile(
          file: "${output}/manifest.json",
          text: JsonOutput.prettyPrint(JsonOutput.toJson(manifest))
        )

        if (!currentBuild.description || !currentBuild.description.contains(artifacts_href)) {
          append_to_build_description(artifacts_href)
        }
      }
      // Test
      if (it.testset != null && !it.testset.isEmpty()) {
        stage("Test ${shortname}") {
          def img_url = "${env.JENKINS_URL}/${artifacts}/${it.target}/${manifest.image}"
          def build_href = "<a href=\"${env.BUILD_URL}\">${env.JOB_NAME}#${env.BUILD_ID}</a>"
          // x1-sec-boot is available only in prod
          def secboot = manifest.uefi.signed && env.CI_ENV == "prod"
          def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
            parameters: [
              string(name: "IMG_URL", value: img_url),
              string(name: "TESTSET", value: it.testset),
              string(name: "DESC", value: "Triggered by ${build_href}<br>(${shortname})"),
              string(name: "TESTAGENT_HOST", value: testagent_host),
              booleanParam(name: "USE_FLAKE_PINNED_CI_TEST", value: env.CI_ENV == "release"),
              booleanParam(name: "RELOAD_ONLY", value: false),
              booleanParam(name: "SECUREBOOT", value: secboot),
            ],
          )
          println("ghaf-hw-test log '${shortname}:")
          sh "cat /var/lib/jenkins/jobs/ghaf-hw-test/builds/${job.number}/log | sed 's/^/    /'"
          if (job.result != "SUCCESS") {
            unstable("FAILED: ${shortname} ${it.testset}")
            currentBuild.result = "FAILURE"
            append_to_build_description("<a href=\"${job.absoluteUrl}\">⛔ ${shortname}</a>")
          }
          copyArtifacts(
            projectName: "ghaf-hw-test",
            selector: specific("${job.number}"),
            target: "${output}/test-results",
            optional: true,
          )
        }
      }
    }
  }
  return pipeline
}

def set_github_commit_status(
  String message,
  String state,
  String commit,
  String project = "tiiuae/ghaf",
  String context = "jenkins-pre-merge") {
  if (!commit) {
    println "Skip setting GitHub commit status"
    return
  }
  println "Setting GitHub commit status"
  withCredentials([string(credentialsId: 'jenkins-github-commit-status-token', variable: 'TOKEN')]) {
    env.TOKEN = "$TOKEN"
    String status_url = "https://api.github.com/repos/$project/statuses/$commit"
    sh """
      # set -x
      curl -H \"Authorization: token \$TOKEN\" \
        -X POST \
        -d '{\"description\": \"$message\", \
             \"state\": \"$state\", \
             \"context\": "$context", \
             \"target_url\" : \"$BUILD_URL\" }' \
        ${status_url}
    """
  }
}

return this
