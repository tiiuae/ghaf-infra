// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

import groovy.json.JsonOutput

private def pipeline_model_call(Closure body) {
  try {
    return body()
  } catch (IllegalArgumentException e) {
    error(e.message)
  }
}

private def ghaf_flake_ref(String repo, String rev) {
  def normalizedRepo = repo.trim()
  if (!normalizedRepo.startsWith("https://")) {
    error("Unsupported Ghaf repository URL '${repo}': expected an HTTPS remote")
  }
  normalizedRepo = "git+${normalizedRepo}".replaceAll('/+$', '')
  def separator = normalizedRepo.contains('?') ? '&' : '?'
  return "${normalizedRepo}${separator}rev=${rev}"
}

private def withRedundancyRouter(String object, Closure body) {
  lock('signing') {
    def signingEnv = readJSON text: artifactSupport.run_cmd("select-pkcs11-node ${object}")
    withEnv([
      "PKCS11_PROXY_SOCKET=${signingEnv.socket}" // overrides the socket with one that works
    ]) {
      println "Proceeding to sign with ${signingEnv}"
      body(signingEnv)
    }
  }
}

private def run_optional_stage(boolean enabled, String stageName, Closure body) {
  if (enabled) {
    stage(stageName) { body() }
  }
}

private def empty_signature() { [path: null, signing_key: null, signing_proxy: null] }

private def record_signature(Map target, Map signingCtx, String path = null) {
  if (path != null) target.path = path
  target.signing_key = signingCtx.uri
  target.signing_proxy = signingCtx.socket
}

def create_pipeline(
  List<Map> targets,
  String testagent_host = null,
  String target_flake_ref = null,
  Map options = [:]) {
  def pipeline = [:]
  def stamp = artifactSupport.run_cmd('date +"%Y%m%d_%H%M%S%3N"')
  def target_commit = artifactSupport.run_cmd('git rev-parse HEAD')
  def target_repo = artifactSupport.run_cmd('git remote get-url origin || git remote get-url pr_origin')
  // Pre-merge jobs can override this with a PR merge ref, which is required
  // to make GitHub's synthetic merge commit fetchable on downstream test agents.
  target_flake_ref = target_flake_ref ?: ghaf_flake_ref(target_repo, target_commit)
  def host_name = artifactSupport.run_cmd('hostname')
  def host_revision = artifactSupport.run_cmd('/run/current-system/sw/bin/nixos-version --configuration-revision')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${target_commit}"
  def artifacts_local_dir = "/var/lib/jenkins/${artifacts}"
  def artifacts_href = "<a href=\"/${artifacts}\">📦 Artifacts</a>"
  def ci_env = env.CI_ENV
  def immutable_tag = "${ci_env}-${stamp}-${target_commit}"
  def signing_possible = ci_env != 'vm'
  def ghaf_checkout = pwd()
  def parallel_tests = options.get('parallel_tests', true)

  stage("Eval") {
    lock('evaluator') {
      sh 'bash -o pipefail -c "nix flake show --all-systems | ansi2txt"'
    }
  }
  targets.each { raw_target_config ->
    def target_config = pipeline_model_call {
      pipelineModel.normalize_build_config(
        raw_target_config,
        signing_possible,
        ci_env,
        testagent_host
      )
    }
    def build_target_name = target_config.target
    def build_shortname = target_config.shortname
    def normalized_test_runs = target_config.test_runs
    def output = "${artifacts_local_dir}/${build_target_name}"
    def local_target_ref = "${ghaf_checkout}#${build_target_name}"

    def manifest = [
      ci_env: ci_env,
      job: [
        name: env.JOB_NAME,
        build_id: env.BUILD_ID,
        build_url: env.BUILD_URL,
      ],
      source: [
        repository: target_repo,
        ref: target_commit,
        revision: target_commit,
        flake_ref: target_flake_ref,
      ],
      target: build_target_name,
      build: [
        ts_begin: null,
        ts_finished: null,
      ],
      images: [],
      uefi: [
        signed: false,
        reason: null,
        image_path: null,
        signing_key: null,
        signing_proxy: null,
      ],
      attestations: [
        provenance: [
          path: null,
          signature: empty_signature(),
        ],
        sbom_csv: [
          path: null,
        ],
        sbom_cyclonedx: [
          path: null,
        ],
        sbom_spdx: [
          path: null,
        ],
      ],
    ]
    def oci_result = null
    def provenance_policy_passed = null
    def provenance_policy_failure = null
    def result_file_for = { Map testRun ->
      "${output}/test-results/${testRun.test_path_key}/result.json"
    }
    def write_test_results = { List finalTestEntries ->
      def testResults = [
        target: build_target_name,
        tests: finalTestEntries,
      ]
      if (provenance_policy_passed != null) {
        testResults.provenance_policy_passed = provenance_policy_passed
      }
      writeFile(
        file: "${output}/test-results.json",
        text: JsonOutput.prettyPrint(JsonOutput.toJson(testResults))
      )
    }
    def write_manifest = {
      writeFile(
        file: "${output}/manifest.json",
        text: JsonOutput.prettyPrint(JsonOutput.toJson(manifest))
      )
    }
    def persist_test_result = { Map testRun, Map result = [:] ->
      def entry = pipeline_model_call { pipelineModel.test_result_entry(testRun, result) }
      artifactSupport.with_controller_workspace(ghaf_checkout) {
        sh "mkdir -v -p '${output}/test-results/${testRun.test_path_key}'"
        writeFile(
          file: result_file_for(testRun),
          text: JsonOutput.prettyPrint(JsonOutput.toJson(entry))
        )
      }
      return entry
    }

    if (target_config.no_image) {
      manifest.uefi.reason = "no_image"
    } else if (!signing_possible) {
      manifest.uefi.reason = "signing_not_possible"
    } else if (!target_config.uefi_sign_requested) {
      manifest.uefi.reason = "not_requested"
    }

    pipeline[build_target_name] = {
      artifactSupport.with_controller_workspace(ghaf_checkout) {
        stage("Build ${build_shortname}") {
          sh "mkdir -v -p ${output}"

          manifest.build.ts_begin = artifactSupport.run_cmd('date +%s')
          lock(label: 'nix-build', quantity: 1) {
            sh "nix build --fallback -v .#${build_target_name} --out-link ${output}/unsigned-output"
          }
          manifest.build.ts_finished = artifactSupport.run_cmd('date +%s')
        }
        run_optional_stage(
          target_config.provenance_requested,
          "Provenance ${build_shortname}"
        ) {
          def ext_params = """
            {
              "target": {
                "name": "${build_target_name}",
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
              while ! provenance ${output}/unsigned-output --recursive --out ${output}/attestations/provenance.json; do
                echo "provenance attempt=\$attempt failed"
                if (( \$attempt >= \$max_attempts )); then
                  exit 1
                fi
                attempt=\$(( \$attempt + 1 ))
                sleep 30
              done
              echo "provenance attempt=\$attempt passed"
            """
            manifest.attestations.provenance.path = "attestations/provenance.json"
          }
        }
        run_optional_stage(
          target_config.build_otapin_requested,
          "OTA Build ${build_shortname}"
        ) {
          def ota_target = build_target_name.tokenize('.').last()
          sh """
            mkdir -v -p ${ota_target}; cd ${ota_target}
            nixos-rebuild build --fallback --flake .#${ota_target}
            mv result ${artifacts_local_dir}/otapin.${ota_target}
            nix-store --add-root ${artifacts_local_dir}/otapin.${ota_target} \
              -r ${artifacts_local_dir}/otapin.${ota_target}
          """
        }
        run_optional_stage(
          target_config.sbom_requested,
          "SBOM ${build_shortname}"
        ) {
          def outdir = "${output}/attestations"
          sh """
            mkdir -v -p ${outdir}
            sbomnix '${local_target_ref}' \
              --csv ${outdir}/sbom.csv \
              --cdx ${outdir}/sbom.cdx.json \
              --spdx ${outdir}/sbom.spdx.json
          """
          manifest.attestations.sbom_csv.path = "attestations/sbom.csv"
          manifest.attestations.sbom_cyclonedx.path = "attestations/sbom.cdx.json"
          manifest.attestations.sbom_spdx.path = "attestations/sbom.spdx.json"
        }
        run_optional_stage(
          signing_possible && target_config.provenance_requested,
          "Sign (SLSA) provenance ${build_shortname}"
        ) {
          withRedundancyRouter("GhafInfraSignProv") { ctx ->
            sh """
              openssl pkeyutl -sign -rawin \
                -inkey "${ctx.uri}" \
                -out ${output}/attestations/provenance.json.sig \
                -in ${output}/attestations/provenance.json
            """
            record_signature(manifest.attestations.provenance.signature, ctx, "attestations/provenance.json.sig")
          }
        }
        run_optional_stage(
          ci_env == "release" && !target_config.no_image && target_config.provenance_requested,
          "Provenance policy ${build_shortname}"
        ) {
          def policy_status = sh(
            script: """
            policy-checker '${output}/attestations/provenance.json' \
              --sig '${output}/attestations/provenance.json.sig' \
              --policy /etc/jenkins/provenance-trust-policy.yaml
            """,
            returnStatus: true
          )
          provenance_policy_passed = policy_status == 0
          write_test_results([])
          if (!provenance_policy_passed) {
            provenance_policy_failure = "Provenance trust policy failed for ${build_shortname}"
            echo(provenance_policy_failure)
          }
        }
        run_optional_stage(
          !target_config.no_image,
          "Find image ${build_shortname}"
        ) {
          def img_paths = artifactSupport.run_cmd(
            "find -L ${output}/unsigned-output -regex '.*\\.\\(img\\|raw\\|zst\\|iso\\)\$' -print | sort"
          )
          def images = img_paths.split('\n').findAll { it }
          if (images.isEmpty()) {
            error("No image found!")
          }
          manifest.images = images.collect { img_path ->
            def relpath = img_path - "${output}/"
            [
              path: relpath,
              role: artifactSupport.image_role(relpath),
              signature: empty_signature(),
            ]
          }
        }
        run_optional_stage(
          !target_config.no_image && signing_possible && target_config.uefi_sign_requested,
          "Sign (UEFI) ${build_shortname}"
        ) {
          def tmpdir = artifactSupport.build_tmpdir("uefisign-${build_shortname}")
          def uefi_image = null
          if (manifest.images.size() == 1) {
            uefi_image = manifest.images[0]
          } else {
            error("UEFI signing for multi-image target ${build_shortname} is not implemented yet")
          }
          def img_name = artifactSupport.path_basename(uefi_image.path)
          def signer = build_target_name.contains("nvidia-jetson-orin") ? "uefisign-simple" : "uefisign"

          try {
            sh """
              rm -rf '${tmpdir}'
              mkdir -p '${tmpdir}'
            """

            withRedundancyRouter("uefi-ghaf-db") { ctx ->
              sh """
                ${signer} /etc/jenkins/keys/secboot/DB.pem \
                  "${ctx.uri}" \
                  ${output}/${uefi_image.path} \
                  '${tmpdir}'
              """
              record_signature(manifest.uefi, ctx)
            }

            sh """
              mkdir -p '${output}/images'
              mv '${tmpdir}/signed_${img_name}' '${output}/images/${img_name}'
            """
            uefi_image.path = "images/${img_name}"
            manifest.uefi.signed = true
            manifest.uefi.image_path = "images/${img_name}"
            manifest.uefi.reason = null
          } finally {
            sh "rm -rf '${tmpdir}'"
          }
        }
        run_optional_stage(
          !target_config.no_image && signing_possible,
          "Sign (SLSA) image ${build_shortname}"
        ) {
          withRedundancyRouter("GhafInfraSignECP256") { ctx ->
            sh "mkdir -p ${output}/images"
            manifest.images.each { image ->
              def img_name = artifactSupport.path_basename(image.path)
              record_signature(image.signature, ctx, "images/${img_name}.sig")
              sh """
                openssl dgst -sha256 -sign \
                  "${ctx.uri}" \
                  -out ${output}/${image.signature.path} \
                  ${output}/${image.path}
              """
            }
          }
        }
        stage("Link artifacts ${build_shortname}") {
          sh "mkdir -p ${output}/images"
          manifest.images.each { image ->
            def img_name = artifactSupport.path_basename(image.path)
            def image_link = "images/${img_name}"
            if (image.path && image.path != image_link) {
              sh "ln -s ${output}/${image.path} ${output}/${image_link}"
              image.path = image_link
            }
          }

          write_manifest()

          artifactSupport.append_to_build_description(artifacts_href, true)
          artifactSupport.append_to_build_description("OCI Tag: ${pipelineModel.html_escape(immutable_tag)}", true)
        }
        run_optional_stage(
          !target_config.no_image,
          "Publish OCI ${build_shortname}"
        ) {
          withCredentials([string(credentialsId: 'oci_registry_password', variable: 'OCI_PASSWORD')]) {
            def oci_repository =
              "ghaf/${env.JOB_BASE_NAME.replaceFirst('^ghaf-', '')}/${build_target_name.replaceFirst('^packages\\.', '')}"
            def oci_result_json = "${output}/oci-result.json"
            def oci_tags = []
            oci_tags << "${ci_env}-latest"
            def oci_alias_args = oci_tags.collect { "--tag '${it}'" }.join(" \\\n                ")
            def oci_alias_args_block = oci_alias_args ? " \\\n                ${oci_alias_args}" : ""
            sh """
              oci-publish target \
                --target-dir '${output}' \
                --repository '${oci_repository}' \
                --primary-tag '${immutable_tag}' \
                --result-json '${oci_result_json}'${oci_alias_args_block}
            """
            oci_result = readJSON file: oci_result_json
          }
        }
      }

      def test_failure_message = null
      if (!normalized_test_runs.isEmpty()) {
        if (manifest.images.size() != 1) {
          error("Multi-image hardware tests are not implemented for ${build_shortname}; found ${manifest.images.size()} images")
        }
        def tests_completed = true
        try {
          def test_branches = [:]
          def runCount = normalized_test_runs.size()
          def hw_test_stage_name =
            runCount > 1 ? "HW tests ${build_shortname} (${runCount})" : "HW test ${build_shortname}"
          def all_tests_skipped = normalized_test_runs.every { it.initial_status == 'SKIPPED' }
          normalized_test_runs.each { localTestRun ->
            test_branches[localTestRun.stage_name] = {
              stage(localTestRun.stage_name) {
                if (localTestRun.initial_status == 'SKIPPED') {
                  persist_test_result(localTestRun, [:])
                  echo("Skipping hardware test ${localTestRun.id}: ${localTestRun.initial_reason}")
                  // Mark the child stage explicitly as skipped so graph views
                  // do not misattribute sibling failures to this branch.
                  org.jenkinsci.plugins.pipeline.modeldefinition.Utils.markStageSkippedForConditional(
                    localTestRun.stage_name
                  )
                  return
                }

                def job = null
                try {
                  job = hwTestUtils.run_hw_test(
                    build_shortname,
                    localTestRun.target,
                    localTestRun.id,
                    localTestRun.testset,
                    localTestRun.effective_testagent_host,
                    oci_result,
                    localTestRun.secureboot,
                    ci_env,
                    localTestRun.get('device_tag', null)
                  )
                  persist_test_result(localTestRun, [job: job])
                  artifactSupport.with_controller_workspace(ghaf_checkout) {
                    hwTestUtils.collect_hw_test_result(
                      localTestRun.id,
                      localTestRun.test_path_key,
                      localTestRun.secureboot,
                      output,
                      job
                    )
                  }
                  persist_test_result(localTestRun, [status: job.result ?: 'UNKNOWN', job: job])
                } catch (Exception e) {
                  def result = [status: 'ERROR', reason: e.message]
                  if (job != null) result.job = job
                  persist_test_result(localTestRun, result)
                  artifactSupport.append_to_build_description("⛔ ${pipelineModel.html_escape(localTestRun.id)}")
                  throw e
                }
              }
            }
          }

          stage(hw_test_stage_name) {
            if (parallel_tests) {
              parallel test_branches
            } else {
              test_branches.each { key, value -> value() }
            }
            if (all_tests_skipped) {
              org.jenkinsci.plugins.pipeline.modeldefinition.Utils.markStageSkippedForConditional(
                hw_test_stage_name
              )
            }
          }
        } catch (Exception e) {
          if (e.getClass().getName() == 'org.jenkinsci.plugins.workflow.steps.FlowInterruptedException') {
            throw e
          }
          tests_completed = false
          test_failure_message = e.message ?: e.toString()
        } finally {
          stage("Publish test results ${build_shortname}") {
            artifactSupport.with_controller_workspace(ghaf_checkout) {
              def finalTestEntries = normalized_test_runs.collect { testRun ->
                def resultFile = result_file_for(testRun)
                if (sh(script: "test -f '${resultFile}'", returnStatus: true) == 0) {
                  return readJSON(file: resultFile, returnPojo: true)
                }
                if (testRun.initial_status != null) {
                  return pipeline_model_call { pipelineModel.test_result_entry(testRun) }
                }
                return pipeline_model_call {
                  pipelineModel.test_result_entry(testRun, [
                    status: 'UNKNOWN',
                    reason: 'missing_result',
                  ])
                }
              }
              write_test_results(finalTestEntries)
              if (ci_env != "vm" && tests_completed) {
                if (sh(
                  script: "test -d '${output}/test-results'",
                  returnStatus: true
                ) != 0) {
                  error("Missing test results for ${build_shortname}: ${output}/test-results")
                }
                withCredentials([string(credentialsId: 'oci_registry_password', variable: 'OCI_PASSWORD')]) {
                  sh """
                    oci-publish test-results \
                      --results-dir '${output}/test-results' \
                      --subject-reference '${oci_result.primary.reference}'
                  """
                }
              } else if (ci_env != "vm") {
                echo("Skipping OCI test result publish for failed ${build_shortname} tests")
              }
            }
          }
        }
      }
      run_optional_stage(
        ci_env == "release" && !target_config.no_image && target_config.provenance_requested,
        "Release policy ${build_shortname}"
      ) {
        artifactSupport.with_controller_workspace(ghaf_checkout) {
          def outdir = "${output}/attestations"
          def policy_status = sh(
            script: """
            policy-checker release '${output}' \
              --oci-result '${output}/oci-result.json' \
              --policy /etc/jenkins/release-policy.yaml \
              --out '${outdir}/release-policy.json'
            """,
            returnStatus: true
          )
          if (
            policy_status != 0 &&
            sh(script: "test -f '${outdir}/release-policy.json'", returnStatus: true) != 0
          ) {
            error("Release policy failed before writing attestation for ${build_shortname}")
          }

          withRedundancyRouter("GhafInfraSignProv") { ctx ->
            sh """
              openssl pkeyutl -sign -rawin \
                -inkey "${ctx.uri}" \
                -out ${outdir}/release-policy.json.sig \
                -in ${outdir}/release-policy.json
            """
          }

          withCredentials([string(credentialsId: 'oci_registry_password', variable: 'OCI_PASSWORD')]) {
            sh """
              oci-publish release-attestation \
                --target-dir '${output}' \
                --subject-reference '${oci_result.primary.reference}'
            """
          }

          if (policy_status != 0) {
            unstable("Release policy failed for ${build_shortname}")
          }
        }
      }
      if (test_failure_message != null) {
        error("Hardware tests failed for ${build_shortname}: ${test_failure_message}")
      }
      if (provenance_policy_failure != null) {
        error(provenance_policy_failure)
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
