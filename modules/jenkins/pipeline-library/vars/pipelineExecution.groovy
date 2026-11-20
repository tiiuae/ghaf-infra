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

private def withRedundancyRouter(String purpose, Closure body) {
  lock('signing') {
    def signingEnv = readJSON text: artifactSupport.run_cmd("select-pkcs11-node ${purpose}")
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

private def signature_entry(Map ctx, String path) { [path: path, signing_key: ctx.uri] }

private def find_main_image(String directory, String preferred = null) {
  if (preferred) {
    if (!fileExists("${directory}/${preferred}")) error("Main image '${preferred}' not found in '${directory}'")
    return preferred
  }
  def candidates = sh(
    script: "find -L ${artifactSupport.shell_quote(directory)} -type f -regextype posix-extended -regex '.*\\.(img|raw|iso)(\\.zst)?' -printf '%P\\0'",
    returnStdout: true
  ).split('\u0000').findAll { it }
  def depth = -1
  for (def path in candidates) {
    def candidate_depth = path.count('/')
    if (depth < 0 || candidate_depth < depth) depth = candidate_depth
  }
  def images = candidates.findAll { it.count('/') == depth }
  return images.size() == 1 ? images[0] : null
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
  def signing_possible = env.JENKINS_SIGNING_ENABLED == 'true'
  def registry_publish_enabled = env.OCI_PUBLISH_ENABLED == 'true'
  def ghaf_checkout = pwd()
  def parallel_tests = options.get('parallel_tests', true)
  def sendResultsToZephyr = options.get('send_results_to_zephyr', false)
  def hw_test_params = options.get('hw_test_params', [:])
  def source_vsa_required = options.get('source_vsa_required', false)
  def source_vsa_requested = source_vsa_required || options.get('source_vsa', true)
  def source_vsa_file = "${artifactSupport.controller_workdir()}/tmp/source-vsa.sigstore.json"
  def source_vsa_path = null

  run_optional_stage(source_vsa_requested, "Source VSA") {
    sh "mkdir -p '${artifactSupport.controller_workdir()}/tmp'"
    def target_repository = target_repo.replaceAll('/+$', '').replaceFirst(/\.git$/, '').replaceFirst(/^https:\/\/github\.com\//, '')
    def quoted_target_repository = artifactSupport.shell_quote(target_repository)
    def quoted_target_commit = artifactSupport.shell_quote(target_commit)
    def source_vsa_status = 1
    // Recent commits on main may still be waiting for the VSA workflow to publish.
    def source_vsa_attempts = sh(
      script: '''
        git merge-base --is-ancestor HEAD origin/main &&
          test "$(date +%s)" -lt "$(( $(git show -s --format=%ct HEAD) + 3600 ))"
      ''',
      returnStatus: true
    ) == 0 ? 3 : 1
    for (int attempt = 1; attempt <= source_vsa_attempts; attempt++) {
      if (attempt > 1) {
        echo "Retrying Source VSA fetch (attempt ${attempt}/${source_vsa_attempts}) after 30 seconds"
        sleep(time: 30, unit: 'SECONDS')
      }
      source_vsa_status = sh(
        script: """
          source-vsa fetch \
            --repository ${quoted_target_repository} \
            --commit ${quoted_target_commit} \
            --bundle '${source_vsa_file}'
        """,
        returnStatus: true
      )
      if (source_vsa_status == 0) break
    }
    if (source_vsa_status == 0) {
      source_vsa_path = "attestations/source-vsa.sigstore.json"
    } else if (source_vsa_required) {
      error("Source VSA verification failed for ${target_repository}@${target_commit}")
    } else {
      def message = "Source VSA verification unavailable for ${target_repository}@${target_commit}; continuing without it"
      catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE', message: message) {
        error(message)
      }
    }
  }

  stage("Eval") {
    lock('evaluator') {
      sh 'bash -o pipefail -c "nix flake show --all-systems | ansi2txt"'
    }
  }
  def secure_ab_override = ''
  def secure_ab_config_dir = "${artifacts_local_dir}/secure-ab-build-config"
  if (targets.any { it.get('secure_ab', false) }) {
    stage('Secure A/B config') {
      if (!env.JENKINS_SECURE_AB_TRUST_DIR) {
        error('Secure A/B builds require JENKINS_SECURE_AB_TRUST_DIR')
      }
      sh """
        mkdir -p ${artifactSupport.shell_quote(secure_ab_config_dir)}
        for file in PK.crt KEK.crt db.crt update.pub; do
          cp ${artifactSupport.shell_quote(env.JENKINS_SECURE_AB_TRUST_DIR)}/"\$file" ${artifactSupport.shell_quote(secure_ab_config_dir)}/
        done
      """
      writeFile(
        file: "${secure_ab_config_dir}/config.json",
        text: JsonOutput.prettyPrint(JsonOutput.toJson([
          schema_version: 1,
          trust: 'external',
          generation: 1,
          inject_boot_health_failure: false,
        ]))
      )
      secure_ab_override = "--override-input secure-ab-build-config " +
        artifactSupport.shell_quote("path:${secure_ab_config_dir}")
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
    def is_sysupdate_target = target_config.sysupdate
    def normalized_test_runs = target_config.test_runs
    if (!registry_publish_enabled && normalized_test_runs.any { it.initial_status != 'SKIPPED' }) {
      error('Hardware tests require services.ghaf-jenkins.registry.enable')
    }
    def output = "${artifacts_local_dir}/${build_target_name}"

    def manifest = [
      schema_version: 2,
      target: build_target_name,
      source: [flake_ref: target_flake_ref],
      output: [path: 'output'],
      attestations: [:],
    ]
    def build_times = [:]
    def uefi_signing = [:]
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

    pipeline[build_target_name] = {
      artifactSupport.with_controller_workspace(ghaf_checkout) {
        lock(label: 'nix-build', quantity: 1) {
          stage("Build ${build_shortname}") {
            sh "mkdir -v -p ${output}"
            if (source_vsa_path != null) {
              sh "install -Dm644 '${source_vsa_file}' '${output}/attestations/source-vsa.sigstore.json'"
              manifest.attestations.source_vsa = [path: source_vsa_path]
            }
            def system = build_target_name.tokenize('.')[1]
            def remote_stores = readJSON file: '/etc/jenkins/remote-stores.json'
            def remote_store = remote_stores[system]
            def store_args = remote_store ?
              "--store ${artifactSupport.shell_quote(remote_store)} --eval-store auto" : ''

            build_times.ts_begin = artifactSupport.run_cmd('date +%s')

            def build_result = readJSON text: sh(
              script: """
                nix build \
                  --fallback \
                  ${store_args} \
                  --json \
                  --no-link \
                  ${target_config.get('secure_ab', false) ? secure_ab_override : ''} \
                  .#${build_target_name}
              """,
              returnStdout: true
            ).trim()

            build_times.ts_finished = artifactSupport.run_cmd('date +%s')

            def store_path = build_result[0]?.outputs?.out
            if (!store_path) {
              error("Unable to read output path from nix build JSON output")
            }

            // The SSH builder is trusted, but its local build outputs are not binary-cache signed
            // so we need --no-check-sigs
            if (remote_store) {
              sh """
                nix copy \
                  --from ${artifactSupport.shell_quote(remote_store)} \
                  --no-check-sigs \
                  ${artifactSupport.shell_quote(store_path)}
              """
            }

            sh """
              nix-store --add-root ${output}/unsigned-output \
                --realise ${artifactSupport.shell_quote(store_path)}
            """
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
                  "repository": ${JsonOutput.toJson(env.JENKINS_PROVENANCE_REPOSITORY ?: 'https://github.com/tiiuae/ghaf-infra')},
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
              "PROVENANCE_TIMESTAMP_BEGIN=${build_times.ts_begin}",
              "PROVENANCE_TIMESTAMP_FINISHED=${build_times.ts_finished}",
              "PROVENANCE_EXTERNAL_PARAMS=${ext_params}"
            ]) {
              sh "mkdir -v -p ${output}/attestations"
              retry(5) {
                sh """
                  provenance ${output}/unsigned-output \
                    --recursive \
                    --out ${output}/attestations/provenance.json \
                    || { sleep 30; exit 1; }
                """
              }
              manifest.attestations.provenance = [path: 'attestations/provenance.json']
            }
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
            sbomnix '${output}/unsigned-output' \
              --csv ${outdir}/sbom.csv \
              --cdx ${outdir}/sbom.cdx.json \
              --spdx ${outdir}/sbom.spdx.json
          """
          manifest.attestations.sbom_csv = [path: 'attestations/sbom.csv']
          manifest.attestations.sbom_cyclonedx = [path: 'attestations/sbom.cdx.json']
          manifest.attestations.sbom_spdx = [path: 'attestations/sbom.spdx.json']
        }
        run_optional_stage(
          signing_possible && target_config.provenance_requested,
          "Sign (SLSA) provenance ${build_shortname}"
        ) {
          withRedundancyRouter('provenance') { ctx ->
            sh """
              openssl pkeyutl -sign -rawin \
                -inkey "${ctx.uri}" \
                -out ${output}/attestations/provenance.json.sig \
                -in ${output}/attestations/provenance.json
            """
            manifest.attestations.provenance.signature = signature_entry(ctx, 'attestations/provenance.json.sig')
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
              --signing-key '${manifest.attestations.provenance.signature.signing_key}' \
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
          !target_config.no_image && signing_possible && target_config.uefi_sign_requested,
          "Sign (UEFI) ${build_shortname}"
        ) {
          def tmpdir = artifactSupport.build_tmpdir("uefisign-${build_shortname}")
          def unsigned_dir = "${output}/unsigned-output"
          def signer
          def signer_input
          if (is_sysupdate_target) {
            signer = 'uefi-sign-sysupdate'
            signer_input = artifactSupport.run_cmd("find -L '${unsigned_dir}' -maxdepth 1 -name '*.manifest' -printf '%P' -quit")
          } else if (build_target_name.contains('nvidia-jetson-orin')) {
            signer = 'uefisign-orin'
            signer_input = '.'
          } else {
            signer = 'uefisign'
            def input_hint = target_config.image_path && fileExists("${unsigned_dir}/${target_config.image_path}") ? target_config.image_path : null
            signer_input = find_main_image(unsigned_dir, input_hint)
          }
          if (!signer_input) {
            error("UEFI signing requires a main image; set 'image_path' in the target config when selection is ambiguous")
          }
          uefi_signing = [signer: signer, input: signer_input]
          uefi_signing.signer_path = artifactSupport.run_cmd("readlink -f \"\$(command -v ${uefi_signing.signer})\"")

          try {
            sh """
              rm -rf '${tmpdir}'
              mkdir -p '${tmpdir}'
            """

            withRedundancyRouter('uefi') { ctx ->
              uefi_signing.started_on = artifactSupport.run_cmd('date -u +%Y-%m-%dT%H:%M:%SZ')
              sh """
                ${artifactSupport.shell_quote(uefi_signing.signer_path)} "${env.JENKINS_UEFI_CERTIFICATE_FILE}" \
                  "${ctx.uri}" \
                  ${artifactSupport.shell_quote("${unsigned_dir}/${signer_input}")} \
                  '${tmpdir}'
              """
              uefi_signing.finished_on = artifactSupport.run_cmd('date -u +%Y-%m-%dT%H:%M:%SZ')
              uefi_signing.signing_key = ctx.uri
            }
            if (target_config.provenance_requested) {
              def signer_outputs = sh(
                script: "bash -o pipefail -c ${artifactSupport.shell_quote("find -L '${tmpdir}' -type f -printf '%P\\0' | sort -z")}",
                returnStdout: true
              )
              uefi_signing.subjects = signer_outputs.split('\u0000').findAll { it }.collect { path ->
                def digest = artifactSupport.run_cmd(
                  "sha256sum < ${artifactSupport.shell_quote("${tmpdir}/${path}")}"
                ).tokenize()[0]
                [name: path, digest: [sha256: digest]]
              }
            }

            sh """
              chmod -R g+rX '${tmpdir}'
              mv '${tmpdir}' '${output}/output'
            """
            if (is_sysupdate_target) {
              manifest.sysupdate = [path: "output/${artifactSupport.path_basename(signer_input)}"]
              def ota_signature_path = "${manifest.sysupdate.path}.sig"
              sh "mkdir -p '${tmpdir}'"
              sh(label: 'Prepare OTA verification key', script: """
                # Ed25519's fixed raw public-key length, in bytes.
                ed25519_public_key_size=32
                # DER SubjectPublicKeyInfo header followed by a BIT STRING containing the 32-byte public key.
                # Hex: 30 2a 30 05 06 03 2b 65 70 03 21 00; encoded as octal for printf.
                ed25519_spki_header='\\060\\052\\060\\005\\006\\003\\053\\145\\160\\003\\041\\000'
                test "\$(wc -c < ${artifactSupport.shell_quote("${secure_ab_config_dir}/update.pub")})" -eq "\$ed25519_public_key_size"
                printf '%b' "\$ed25519_spki_header" > '${tmpdir}/update-key.der'
                cat ${artifactSupport.shell_quote("${secure_ab_config_dir}/update.pub")} >> '${tmpdir}/update-key.der'
              """)

              def ota_signing_ctx = null
              withRedundancyRouter('ota') { ctx ->
                sh(label: 'Sign finalized OTA manifest', script: """
                  openssl pkeyutl -sign -rawin \
                    -inkey "${ctx.uri}" \
                    -in ${artifactSupport.shell_quote("${output}/${manifest.sysupdate.path}")} \
                    -out '${tmpdir}/manifest.sig'
                """)
                ota_signing_ctx = ctx
              }

              sh(label: 'Verify OTA manifest signature', script: """
                # Ed25519's fixed signature length, in bytes.
                ed25519_signature_size=64
                test "\$(wc -c < '${tmpdir}/manifest.sig')" -eq "\$ed25519_signature_size"
                openssl pkeyutl -verify -rawin -pubin -keyform DER \
                  -inkey '${tmpdir}/update-key.der' \
                  -in ${artifactSupport.shell_quote("${output}/${manifest.sysupdate.path}")} \
                  -sigfile '${tmpdir}/manifest.sig'
              """)

              sh(label: 'Publish verified OTA signature', script: """
                mv '${tmpdir}/manifest.sig' ${artifactSupport.shell_quote("${output}/${ota_signature_path}")}
              """)
              manifest.sysupdate.signature = signature_entry(ota_signing_ctx, ota_signature_path)
            }
          } finally {
            sh "rm -rf '${tmpdir}'"
          }
        }
        run_optional_stage(
          uefi_signing.finished_on != null && target_config.provenance_requested,
          "Provenance (UEFI) ${build_shortname}"
        ) {
          def unsigned_output = artifactSupport.run_cmd("readlink -f ${output}/unsigned-output")
          def unsigned_subject = readJSON(
            text: artifactSupport.run_cmd("""
              jq -c --arg uri ${artifactSupport.shell_quote(unsigned_output)} \
                'first(.subject[] | select(.uri == \$uri)) // {}' \
                ${artifactSupport.shell_quote("${output}/${manifest.attestations.provenance.path}")}
            """),
            returnPojo: true
          )
          if (!unsigned_subject?.digest) {
            error("Build provenance does not identify unsigned output '${unsigned_output}'")
          }
          def sha256 = { String path ->
            artifactSupport.run_cmd("sha256sum < ${artifactSupport.shell_quote(path)}").tokenize()[0]
          }
          def uefi_provenance = [
            _type: 'https://in-toto.io/Statement/v1',
            subject: uefi_signing.subjects,
            predicateType: 'https://slsa.dev/provenance/v1',
            predicate: [
              buildDefinition: [
                buildType: 'https://github.com/tiiuae/ghaf-infra/blob/main/slsa/v1.0/L1/uefi-buildtype.md',
                externalParameters: [input: uefi_signing.input],
                internalParameters: [signer: uefi_signing.signer, signing_key: uefi_signing.signing_key],
                resolvedDependencies: [
                  unsigned_subject,
                  [
                    uri: manifest.attestations.provenance.path,
                    digest: [sha256: sha256("${output}/${manifest.attestations.provenance.path}")],
                  ],
                  [uri: uefi_signing.signer_path, digest: [sha256: sha256(uefi_signing.signer_path)]],
                  [
                    uri: env.JENKINS_UEFI_CERTIFICATE_FILE,
                    digest: [sha256: sha256(env.JENKINS_UEFI_CERTIFICATE_FILE)],
                  ],
                ],
              ],
              runDetails: [
                builder: [id: env.JENKINS_URL, version: ['ghaf-infra': host_revision]],
                metadata: [
                  invocationId: env.BUILD_URL,
                  startedOn: uefi_signing.started_on,
                  finishedOn: uefi_signing.finished_on,
                ],
              ],
            ],
          ]
          def provenance_path = 'attestations/uefi-provenance.json'
          writeFile(file: "${output}/${provenance_path}", text: JsonOutput.prettyPrint(JsonOutput.toJson(uefi_provenance)))
          def attestation = [path: provenance_path]
          withRedundancyRouter('provenance') { ctx ->
            sh """
              openssl pkeyutl -sign -rawin \
                -inkey "${ctx.uri}" \
                -out ${output}/${provenance_path}.sig \
                -in ${output}/${provenance_path}
            """
            attestation.signature = signature_entry(ctx, "${provenance_path}.sig")
          }
          manifest.attestations.uefi_provenance = attestation
        }
        stage("Collect output ${build_shortname}") {
          if (!uefi_signing.finished_on) {
            // Outputs without a main image can link to an entire NixOS system closure.
            sh """
              mkdir -p '${output}/output'
              if test -d '${output}/unsigned-output'; then
                cp -rs${target_config.no_image ? '' : 'L'} --no-preserve=mode '${output}/unsigned-output/.' '${output}/output/'
              else
                ln -s '${output}/unsigned-output' '${output}/output/'\"\$(basename \"\$(readlink -f '${output}/unsigned-output')\")\"
              fi
            """
          }
          if (!target_config.no_image && !is_sysupdate_target) {
            def image_hint = target_config.image_path
            if (image_hint && uefi_signing.finished_on) {
              def signed_image = "signed_${artifactSupport.path_basename(image_hint)}"
              if (fileExists("${output}/output/${signed_image}")) image_hint = signed_image
            }
            def image_path = find_main_image("${output}/output", image_hint)
            if (image_path) manifest.image = [path: "output/${image_path}"]
          }
        }
        run_optional_stage(
          manifest.image != null && signing_possible,
          "Sign (SLSA) image ${build_shortname}"
        ) {
          withRedundancyRouter('image') { ctx ->
            def signature_path = "${manifest.image.path}.sig"
            sh """
              openssl dgst -sha256 -sign "${ctx.uri}" \
                -out ${artifactSupport.shell_quote("${output}/${signature_path}")} \
                ${artifactSupport.shell_quote("${output}/${manifest.image.path}")}
            """
            manifest.image.signature = signature_entry(ctx, signature_path)
          }
        }
        stage("Link artifacts ${build_shortname}") {
          write_manifest()

          artifactSupport.append_to_build_description(artifacts_href, true)
          if (registry_publish_enabled && !target_config.no_image) {
            artifactSupport.append_to_build_description("OCI Tag: ${pipelineModel.html_escape(immutable_tag)}", true)
          }
        }
        run_optional_stage(
          registry_publish_enabled && !target_config.no_image,
          "Publish OCI ${build_shortname}"
        ) {
          withCredentials([string(credentialsId: 'oci_registry_password', variable: 'OCI_PASSWORD')]) {
            def oci_repository =
              "${env.OCI_NAMESPACE ?: 'ghaf'}/${env.JOB_BASE_NAME}/${build_target_name.replaceFirst('^packages\\.', '')}"
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
        if (!manifest.image && normalized_test_runs.any { it.initial_status != 'SKIPPED' }) {
          error("Hardware tests require a main image for ${build_shortname}; set 'image_path' in the target config")
        }
        def tests_completed = true
        try {
          def test_branches = [:]
          def runCount = normalized_test_runs.size()
          def hw_test_stage_name =
            runCount > 1 ? "HW tests ${build_shortname} (${runCount})" : "HW test ${build_shortname}"
          def all_tests_skipped = normalized_test_runs.every { it.initial_status == 'SKIPPED' }
          normalized_test_runs.each { localTestRun ->
            // Jenkins marks skipped stages by name across the whole flow graph,
            // so include the build in pre-skipped stage names.
            def testStageName = localTestRun.initial_status == 'SKIPPED' ?
              "${localTestRun.stage_name} / ${build_shortname}" : localTestRun.stage_name
            test_branches[testStageName] = {
              stage(testStageName) {
                if (localTestRun.initial_status == 'SKIPPED') {
                  persist_test_result(localTestRun, [:])
                  echo("Skipping hardware test ${localTestRun.id}: ${localTestRun.initial_reason}")
                  org.jenkinsci.plugins.pipeline.modeldefinition.Utils.markStageSkippedForConditional(
                    testStageName
                  )
                  return
                }

                def job = null
                try {
                  job = hwTestUtils.run_hw_test(
                    build_shortname,
                    localTestRun.target,
                    localTestRun.id,
                    localTestRun.testset ?: '',
                    localTestRun.effective_testagent_host,
                    oci_result,
                    localTestRun.secureboot,
                    ci_env,
                    localTestRun.get('device_tag', null),
                    sendResultsToZephyr,
                    hw_test_params + (localTestRun.test_tags ? [
                      TEST_TAGS: "[${localTestRun.test_tags.collect { JsonOutput.toJson(it) }.join(',')}]".toString(),
                    ] : [:])
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
              if (registry_publish_enabled && ci_env != "vm" && tests_completed) {
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
              } else if (registry_publish_enabled && ci_env != "vm") {
                echo("Skipping OCI test result publish for failed ${build_shortname} tests")
              }
            }
          }
        }
      }
      run_optional_stage(
        registry_publish_enabled && ci_env == "release" && !target_config.no_image && target_config.provenance_requested,
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

          withRedundancyRouter('release') { ctx ->
            def releaseAttestation = readJSON file: "${outdir}/release-policy.json"
            releaseAttestation.predicate.signing_key = ctx.uri
            writeJSON file: "${outdir}/release-policy.json", json: releaseAttestation
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
  context = context?.trim() ?: "jenkins-pre-merge"
  if (!commit) {
    println "Skip setting GitHub commit status"
    return false
  }
  println "Setting GitHub commit status"
  String status_url = "https://api.github.com/repos/$project/statuses/$commit"
  String payload = JsonOutput.toJson([
    description: message,
    state: state,
    context: context,
    target_url: env.BUILD_URL,
  ])
  try {
    withCredentials([string(credentialsId: 'jenkins-github-commit-status-token', variable: 'TOKEN')]) {
      withEnv([
        "GITHUB_STATUS_PAYLOAD=${payload}",
        "GITHUB_STATUS_URL=${status_url}",
      ]) {
        sh """
          # set -x
          curl --fail-with-body --silent --show-error \
            --retry 3 --retry-delay 2 --retry-all-errors \
            -H \"Authorization: token \$TOKEN\" \
            -H \"Accept: application/vnd.github+json\" \
            -H \"Content-Type: application/json\" \
            -X POST \
            --data-binary \"\$GITHUB_STATUS_PAYLOAD\" \
            \"\$GITHUB_STATUS_URL\"
        """
      }
    }
    return true
  } catch (InterruptedException e) {
    throw e
  } catch (Exception e) {
    println "Failed to set GitHub commit status '${context}' on ${commit}: ${e.message}"
    return false
  }
}
