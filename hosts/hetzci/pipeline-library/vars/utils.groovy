// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

import groovy.json.JsonOutput
import org.jenkinsci.plugins.pipeline.modeldefinition.Utils

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout: true).trim()
}

def run_wget(String url, String to_dir) {
  sh "wget --show-progress --progress=dot:giga --force-directories --timestamping -P ${to_dir} ${url}"
  return run_cmd(
    "wget --force-directories --timestamping -P ${to_dir} ${url} 2>&1 | grep -Po '${to_dir}[^’]+'"
  )
}

def get_test_conf_property(String file_path, String device, String property) {
  def device_data = readJSON file: file_path
  def property_data = "${device_data['addresses'][device][property]}"
  println "Got device '${device}' property '${property}' value: '${property_data}'"
  return property_data
}

def checkout_ci_test_sources(
  String pinned_source_file,
  boolean use_flake_pinned_ci_test,
  String ci_test_repo_branch,
  String ci_test_repo_url) {
  if (use_flake_pinned_ci_test) {
    def pinned_src = run_cmd("cat ${pinned_source_file}")
    println("Using flake-pinned ci-test-automation source: ${pinned_src}")
    sh """
      if [ ! -d "${pinned_src}/Robot-Framework/test-suites" ]; then
        echo "ERROR: invalid ci-test-automation source path '${pinned_src}'"
        exit 1
      fi
      cp -r "${pinned_src}/." .
      chmod -R u+w .
    """
    return
  }
  checkout scmGit(
    branches: [[name: ci_test_repo_branch]],
    userRemoteConfigs: [[url: ci_test_repo_url]]
  )
}

def path_basename(String path) {
  if (path == null) {
    return null
  }
  def idx = path.lastIndexOf('/')
  return idx >= 0 ? path.substring(idx + 1) : path
}

def image_role(String path) {
  def basename = path_basename(path)
  if (basename == null) {
    return null
  }
  return basename.endsWith(".iso") ? "installer" : "disk"
}

def append_to_build_description(String text) {
  lock('build-description') {
    if (!currentBuild.description) {
      currentBuild.description = text
    } else {
      currentBuild.description = "${currentBuild.description}<br>${text}"
    }
  }
}

def ghaf_flake_ref(String repo, String rev) {
  def normalizedRepo = repo.trim()
  if (!normalizedRepo.startsWith("https://")) {
    error("Unsupported Ghaf repository URL '${repo}': expected an HTTPS remote")
  }
  normalizedRepo = "git+${normalizedRepo}"
  normalizedRepo = normalizedRepo.replaceAll('/+$', '')
  def separator = normalizedRepo.contains('?') ? '&' : '?'
  return "${normalizedRepo}${separator}rev=${rev}"
}

@NonCPS
def device_catalog() {
  return [
    [target_substring: "nvidia-jetson-orin-agx64", name: 'OrinAGX64', tag: 'orin-agx-64'],
    [target_substring: "nvidia-jetson-orin-agx", name: 'OrinAGX1', tag: 'orin-agx'],
    [target_substring: "nvidia-jetson-orin-nx", name: 'OrinNX1', tag: 'orin-nx'],
    [target_substring: "lenovo-x1", name: 'LenovoX1-1', tag: 'lenovo-x1'],
    [target_substring: null, name: 'X1-Secure-Boot', tag: 'x1-sec-boot'],
    [target_substring: "dell-latitude-7330", name: 'Dell7330', tag: 'dell-7330'],
    [target_substring: "system76-darp11-b", name: 'DarterPRO', tag: 'darter-pro'],
  ]
}

@NonCPS
// Why NonCPS? Jenkins CPS does not handle regex matchers reliably.
// See: https://stackoverflow.com/a/48465528
def derive_target_name(String imgUrl, String ociTarget) {
  def normalizedTarget = ociTarget?.trim()
  if (normalizedTarget) {
    return normalizedTarget
  }
  if (!imgUrl) {
    return null
  }
  def match = imgUrl =~ /commit_[0-9a-f]{5,40}\/([^\/]+)/
  if (match) {
    return match.group(1)
  }
  return null
}

@NonCPS
def derive_device_info(String target, boolean secureboot) {
  def devices = device_catalog()
  if (target.contains("lenovo-x1")) {
    if (secureboot && !target.contains("installer")) {
      def securebootDevice = devices.find { it.tag == 'x1-sec-boot' }
      return securebootDevice ? [name: securebootDevice.name, tag: securebootDevice.tag] : null
    }
  }
  def device = devices.find { it.target_substring && target.contains(it.target_substring) }
  if (device) {
    return [name: device.name, tag: device.tag]
  }
  return null
}

@NonCPS
def device_name_from_tag(String deviceTag) {
  return device_catalog().find { it.tag == deviceTag }?.name
}

def extra_tag_suffix(String target, String deviceTag) {
  def filters = []
  if (target.contains("lenovo-x1") || target.contains("darp11-b")) {
    filters.add(target.contains("storeDisk") ? 'NOTexcl-storeDisk' : 'NOTstoreDisk-only')
    filters.add(target.contains("installer") ? 'NOTexcl-installer' : 'NOTinstaller-only')
  }
  if (target.contains("lenovo-x1")) {
    filters.add(deviceTag == 'x1-sec-boot' ? 'NOTexcl-secboot' : 'NOTsecboot-only')
  }
  return filters.unique().join('')
}

def boot_tag_for(String deviceTag) {
  return deviceTag == 'x1-sec-boot' ? 'lenovo-x1' : deviceTag
}

def archive_robot_artifacts(String tmp_img_dir, boolean should_archive) {
  if (should_archive) {
    def test_artifacts = '' +
      'Robot-Framework/test-suites/**/*.html, ' +
      'Robot-Framework/test-suites/**/*.xml, ' +
      'Robot-Framework/test-suites/**/*.png, ' +
      'Robot-Framework/test-suites/**/*.jpeg, ' +
      'Robot-Framework/test-suites/**/*.mp4, ' +
      'Robot-Framework/test-suites/**/*.mkv, ' +
      'Robot-Framework/test-suites/**/*.wav, ' +
      'Robot-Framework/test-suites/**/*.txt'
    archiveArtifacts allowEmptyArchive: true, artifacts: test_artifacts
  }
  sh "rm -rf ${tmp_img_dir} || true"
}

def setup_mount_commands(String conf_file_path, String target, String device_name) {
  if (target.contains("microchip-icicle-")) {
    def muxport = get_test_conf_property(conf_file_path, device_name, 'usb_sd_mux_port')
    return [
      mount_cmd: "/run/wrappers/bin/sudo usbsdmux ${muxport} host; sleep 10",
      unmount_cmd: "/run/wrappers/bin/sudo usbsdmux ${muxport} dut",
    ]
  }
  def serial = get_test_conf_property(conf_file_path, device_name, 'usbhub_serial')
  return [
    mount_cmd: "/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}; sleep 10",
    unmount_cmd: "/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}; sleep 10",
  ]
}

def resolve_flash_target(String conf_file_path, String device_name, String mount_cmd, String unmount_cmd) {
  sh mount_cmd
  def dev = get_test_conf_property(conf_file_path, device_name, 'ext_drive_by-id')
  println "Checking that flash target '${dev}' is connected..."
  sh """
    if /run/wrappers/bin/sudo test -f ${dev}; then
      echo "dev ${dev} found as regular file, removing the file and trying re-mount"
      ${unmount_cmd}; /run/wrappers/bin/sudo rm ${dev}; ${mount_cmd}
    fi
    if ! /run/wrappers/bin/sudo test -L ${dev}; then
      echo "Symlink ${dev} not found. Failed to connect target USB disk to test agent."
      echo "Check USB cables. Maybe need to reboot test agent or Acroname USB hub."
      echo "Aborting flashing ${device_name}"
      exit 1
    fi
  """
  return dev
}

def assert_flash_target_unmounted(String dev) {
  sh """
    if /run/wrappers/bin/sudo test -L ${dev}; then
      echo "Symlink ${dev} was found. Failed to unmount target USB disk from test agent."
      exit 1
    fi
  """
}

def withRedundancyRouter(String object, Closure body) {
  def signingEnv = readJSON text: run_cmd("select-pkcs11-node ${object}")
  withEnv([
    "PKCS11_PROXY_SOCKET=${signingEnv.socket}" // overrides the socket with one that works
  ]) {
    println "Proceeding to sign with ${signingEnv}"
    body(signingEnv) // signingEnv object is available for closure
  }
}

@NonCPS
// Why NonCPS? Jenkins CPS does not handle regex matchers reliably.
// See: https://stackoverflow.com/a/48465528
def resolve_ghaf_flake_ref(String explicitFlakeRef, String imgUrl, String ociFlakeRef) {
  def normalizedFlakeRef = explicitFlakeRef?.trim()
  if (normalizedFlakeRef) {
    return normalizedFlakeRef
  }
  def normalizedOciFlakeRef = ociFlakeRef?.trim()
  if (normalizedOciFlakeRef) {
    return normalizedOciFlakeRef
  }
  def match = imgUrl =~ /commit_([a-f0-9]{40})/
  if (match) {
    return "git+https://github.com/tiiuae/ghaf?rev=${match[0][1]}"
  }
  return null
}

@NonCPS
def safe_path_component(String value) {
  return value.replaceAll(/[^A-Za-z0-9_.-]/, '-')
}

def controller_workdir() {
  def rawTag = env.BUILD_TAG ?: "${env.JOB_NAME}-${env.BUILD_NUMBER}"
  def tag = safe_path_component(rawTag)
  if (!tag || tag == 'null-null') {
    error('Cannot derive a unique controller workdir for this build')
  }
  return "/var/lib/jenkins/ghaf-pipeline-workspaces/${tag}"
}

def build_tmpdir(String name) {
  def component = safe_path_component(name)
  if (!component || component == 'null') {
    error("Cannot derive a unique build tmpdir for '${name}'")
  }
  return "${controller_workdir()}/tmp/${component}"
}

def clean_controller_workdir() {
  node('built-in') {
    sh "rm -rf '${controller_workdir()}'"
  }
}

def with_controller_workspace(String workspace, Closure body) {
  node('built-in') {
    dir(workspace) {
      body()
    }
  }
}

def run_hw_test(
  String shortname,
  String testset,
  String testagent_host,
  Map oci_result,
  boolean secureboot,
  String ci_env) {
  // Keep the blocking downstream wait outside node('built-in') so ghaf-hw-test
  // can acquire a controller executor for its own initialization stages.
  def build_href = "<a href=\"${env.BUILD_URL}\">${env.JOB_NAME}#${env.BUILD_ID}</a>"
  def test_params = [
    string(name: "TESTSET", value: testset),
    string(name: "DESC", value: "Triggered by ${build_href}<br>(${shortname})"),
    string(name: "TESTAGENT_HOST", value: testagent_host),
    booleanParam(name: "USE_FLAKE_PINNED_CI_TEST", value: ci_env == "release"),
    booleanParam(name: "RELOAD_ONLY", value: false),
    booleanParam(name: "SECUREBOOT", value: secureboot),
  ]
  if (oci_result == null) {
    error("Missing OCI publish result for ${shortname}; cannot trigger ghaf-hw-test")
  }
  test_params += [
    string(name: "OCI_IMAGE_REF", value: oci_result.primary.reference),
  ]
  def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
    parameters: test_params
  )
  return [
    absoluteUrl: job.absoluteUrl,
    number: job.number,
    result: job.result,
  ]
}

def collect_hw_test_result(
  String shortname,
  String testset,
  String output,
  boolean secureboot,
  Map job) {
  def logPrefix = secureboot ? "ghaf-hw-test log SB '${shortname}:" : "ghaf-hw-test log '${shortname}:"
  println(logPrefix)
  sh "cat /var/lib/jenkins/jobs/ghaf-hw-test/builds/${job.number}/log | sed 's/^/    /'"
  if (job.result != "SUCCESS") {
    unstable("FAILED: ${shortname} ${testset}")
    currentBuild.result = "FAILURE"
    def buildDescriptionName = secureboot ? "${shortname} (SB)" : shortname
    append_to_build_description("<a href=\"${job.absoluteUrl}\">⛔ ${buildDescriptionName}</a>")
  }
  def artifactsTarget = secureboot ? "${output}/test-results/secureboot" : "${output}/test-results"
  copyArtifacts(
    projectName: "ghaf-hw-test",
    selector: specific("${job.number}"),
    target: artifactsTarget,
    optional: true
  )
}

def create_pipeline(List<Map> targets, String testagent_host = null, String target_flake_ref = null) {
  def pipeline = [:]
  def stamp = run_cmd('date +"%Y%m%d_%H%M%S%3N"')
  def target_commit = run_cmd('git rev-parse HEAD')
  def target_repo = run_cmd('git remote get-url origin || git remote get-url pr_origin')
  // Pre-merge jobs can override this with a PR merge ref, which is required
  // to make GitHub's synthetic merge commit fetchable on downstream test agents.
  target_flake_ref = target_flake_ref ?: ghaf_flake_ref(target_repo, target_commit)
  def host_name = run_cmd('hostname')
  def host_revision = run_cmd('/run/current-system/sw/bin/nixos-version --configuration-revision')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${target_commit}"
  def artifacts_local_dir = "/var/lib/jenkins/${artifacts}"
  def artifacts_href = "<a href=\"/${artifacts}\">📦 Artifacts</a>"
  def ci_env = env.CI_ENV
  def immutable_tag = "${ci_env}-${stamp}-${target_commit}"
  def signing_possible = ci_env != 'vm'
  def ghaf_checkout = pwd()

  // Evaluate
  stage("Eval") {
    lock('evaluator') {
      sh 'bash -o pipefail -c "nix flake show --all-systems | ansi2txt"'
    }
  }
  targets.each { target_config ->
    def target_name = target_config.target
    def shortname = target_name.substring(target_name.lastIndexOf('.') + 1)
    def output = "${artifacts_local_dir}/${target_name}"
    def local_target_ref = "${ghaf_checkout}#${target_name}"
    def no_image = target_config.get('no_image', false)
    def uefi_sign_requested = target_config.get('uefisign', false) || target_config.get('uefisigniso', false)
    def can_uefi_sign = !no_image && signing_possible && uefi_sign_requested
    def testset = target_config.get('testset', null)
    def has_testset = testset != null && !testset.isEmpty()
    def test_secboot_requested = target_config.get('test_secboot', false)
    def run_secboot_test = test_secboot_requested && can_uefi_sign && ci_env == "prod"
    def provenance_requested = target_config.get('provenance', true)
    def build_otapin_requested = target_config.get('build_otapin', false)
    def sbom_requested = target_config.get('sbom', false)

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
      target: target_name,
      build: [
        ts_begin: null,
        ts_finished: null,
      ],
      image: [
        path: null,
        role: null,
        signature: [
          path: null,
          signing_key: null,
          signing_proxy: null,
        ],
      ],
      uefi: [
        signed: false,
        reason: null,
        signing_key: null,
        signing_proxy: null,
      ],
      attestations: [
        provenance: [
          path: null,
          signature: [
            path: null,
            signing_key: null,
            signing_proxy: null,
          ],
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
    if (no_image) {
      manifest.uefi.reason = "no_image"
    } else if (!signing_possible) {
      manifest.uefi.reason = "signing_not_possible"
    } else if (!uefi_sign_requested) {
      manifest.uefi.reason = "not_requested"
    }

    pipeline["${target_name}"] = {
      with_controller_workspace(ghaf_checkout) {
        // Build
        stage("Build ${shortname}") {
          sh "mkdir -v -p ${output}"

          manifest.build.ts_begin = run_cmd('date +%s')
          lock(label: 'nix-build', quantity: 1) {
            sh "nix build --fallback -v .#${target_name} --out-link ${output}/unsigned-output"
          }
          manifest.build.ts_finished = run_cmd('date +%s')
        }
        // Provenance
        if (provenance_requested) {
          stage("Provenance ${shortname}") {
            def ext_params = """
              {
                "target": {
                  "name": "${target_name}",
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
        }
        // Build OTA pin
        if (build_otapin_requested) {
          stage("OTA Build ${shortname}") {
            def ota_target = target_name.tokenize('.').last()
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
        if (sbom_requested) {
          stage("SBOM ${shortname}") {
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
        }
        // Signing stages
        // Skip signing stages only in vm, where the signing proxy is not configured.
        if (signing_possible && provenance_requested) {
          stage("Sign (SLSA) provenance ${shortname}") {
            lock('signing') {
              withRedundancyRouter("GhafInfraSignProv") { ctx ->
                sh """
                  openssl pkeyutl -sign -rawin \
                    -inkey "${ctx.uri}" \
                    -out ${output}/attestations/provenance.json.sig \
                    -in ${output}/attestations/provenance.json
                """
                manifest.attestations.provenance.signature.path = "attestations/provenance.json.sig"
                manifest.attestations.provenance.signature.signing_key = ctx.uri
                manifest.attestations.provenance.signature.signing_proxy = ctx.socket
              }
            }
          }
        }
        if (!no_image) {
          stage("Find image ${shortname}") {
            def img_path = run_cmd("find -L ${output}/unsigned-output -regex '.*\\.\\(img\\|raw\\|zst\\|iso\\)\$' -print -quit")
            if (!img_path) {
              error("No image found!")
            }
            manifest.image.path = img_path - "${output}/"
            manifest.image.role = image_role(manifest.image.path)
          }
          if (signing_possible) {
            if (uefi_sign_requested) {
              stage("Sign (UEFI) ${shortname}") {
                def tmpdir = build_tmpdir("uefisign-${shortname}")
                def img_name = path_basename(manifest.image.path)

                def signer = "uefisign"
                if (target_name.contains("nvidia-jetson-orin")) {
                  signer = "uefisign-simple"
                }

                try {
                  sh """
                    rm -rf '${tmpdir}'
                    mkdir -p '${tmpdir}'
                  """

                  lock('signing') {
                    withRedundancyRouter("uefi-ghaf-db") { ctx ->
                      sh """
                        ${signer} /etc/jenkins/keys/secboot/DB.pem \
                          "${ctx.uri}" \
                          ${output}/${manifest.image.path} \
                          '${tmpdir}'
                      """
                      manifest.uefi.signing_key = ctx.uri
                      manifest.uefi.signing_proxy = ctx.socket
                    }
                  }

                  sh "mv '${tmpdir}/signed_${img_name}' '${output}/${img_name}'"
                  // replace original image with uefisigned one
                  manifest.image.path = img_name
                  manifest.uefi.signed = true;
                  manifest.uefi.reason = null
                } finally {
                  sh "rm -rf '${tmpdir}'"
                }
              }
            }
            stage("Sign (SLSA) image ${shortname}") {
              lock('signing') {
                def img_name = path_basename(manifest.image.path)
                // sign the current main image be it unsigned or uefisigned
                manifest.image.signature.path = "${img_name}.sig"
                withRedundancyRouter("GhafInfraSignECP256") { ctx ->
                  sh """
                    openssl dgst -sha256 -sign \
                      "${ctx.uri}" \
                      -out ${output}/${manifest.image.signature.path} \
                      ${output}/${manifest.image.path}
                  """
                  manifest.image.signature.signing_key = ctx.uri
                  manifest.image.signature.signing_proxy = ctx.socket
                }
              }
            }
          }
        }
        // Link artifacts
        stage("Link artifacts ${shortname}") {
          if (manifest.image.path && !manifest.uefi.signed) {
            def img_name = path_basename(manifest.image.path)
            // make symlink from output root to original image if not using uefisigned
            sh "ln -s ${output}/${manifest.image.path} ${output}/${img_name}"
            manifest.image.path = img_name
          }

          writeFile(
            file: "${output}/manifest.json",
            text: JsonOutput.prettyPrint(JsonOutput.toJson(manifest))
          )

          if (!currentBuild.description || !currentBuild.description.contains(artifacts_href)) {
            append_to_build_description(artifacts_href)
          }
        }
        if (!no_image) {
          stage("Publish OCI ${shortname}") {
            if (sh(
              script: 'command -v oci-publish >/dev/null 2>&1',
              returnStatus: true
            ) != 0) {
              println("Skipping OCI publish ${shortname}: oci-publish is not installed")
            } else {
              withCredentials([string(credentialsId: 'oci_registry_password', variable: 'OCI_PASSWORD')]) {
                def job_name = env.JOB_BASE_NAME.replaceFirst('^ghaf-', '')
                def oci_target_name = target_name.replaceFirst('^packages\\.', '')
                def oci_repository = "ghaf/${job_name}/${oci_target_name}"
                def oci_result_json = "${output}/oci-result.json"
                sh """
                  oci-publish target \
                    -d '${output}' \
                    -r '${oci_repository}' \
                    -t '${immutable_tag}' \
                    -o '${oci_result_json}'
                """
                oci_result = readJSON file: oci_result_json
              }
            }
          }
        }
      }
      // Test
      if (has_testset) {
        def testStageName = "Test ${shortname}"
        stage(testStageName) {
          if (ci_env == "vm") {
            Utils.markStageSkippedForConditional(testStageName)
            println("Skipping hardware tests for ${shortname}: CI_ENV is vm")
          } else {
            def job = run_hw_test(shortname, testset, testagent_host, oci_result, false, ci_env)
            with_controller_workspace(ghaf_checkout) {
              collect_hw_test_result(shortname, testset, output, false, job)
            }
          }
        }
        // Run an additional secure boot test only when the target requests it and
        // secure-boot-capable hardware is available in prod. X1 update tests
        // still need secure boot disabled, even for signed images, so the
        // regular test run cannot be replaced with a secure boot-only run.
        if (test_secboot_requested) {
          def testSecbootStageName = "Test SB ${shortname}"
          println(
            "Secure boot test decision ${shortname}: " +
              "requested=${test_secboot_requested}, " +
              "can_uefi_sign=${can_uefi_sign}, " +
              "ci_env=${ci_env}, " +
              "run=${run_secboot_test}"
          )
          if (run_secboot_test) {
            stage(testSecbootStageName) {
              def job = run_hw_test(shortname, testset, testagent_host, oci_result, true, ci_env)
              with_controller_workspace(ghaf_checkout) {
                collect_hw_test_result(shortname, testset, output, true, job)
              }
            }
          } else {
            stage(testSecbootStageName) {
              Utils.markStageSkippedForConditional(testSecbootStageName)
            }
          }
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
