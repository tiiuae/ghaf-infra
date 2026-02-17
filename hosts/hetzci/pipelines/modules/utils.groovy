#!/usr/bin/env groovy

import groovy.json.JsonOutput

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout:true).trim()
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
  // Evaluate
  stage("Eval") {
    lock('evaluator') {
      sh 'nix flake show --all-systems | ansi2txt'
    }
  }
  targets.each {
    def shortname = it.target.substring(it.target.lastIndexOf('.') + 1)
    def build_beg = ''
    def build_end = ''
    pipeline["${it.target}"] = {
      // Build
      stage("Build ${shortname}") {
        build_beg = run_cmd('date +%s')
        sh "nix build --fallback -v .#${it.target} --out-link ${artifacts_local_dir}/${it.target}"
        build_end = run_cmd('date +%s')
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
            "PROVENANCE_TIMESTAMP_BEGIN=${build_beg}",
            "PROVENANCE_TIMESTAMP_FINISHED=${build_end}",
            "PROVENANCE_EXTERNAL_PARAMS=${ext_params}"
          ]) {
            sh """
              attempt=1; max_attempts=5;
              while ! provenance ${artifacts_local_dir}/${it.target}/ --recursive --out ${it.target}.json; do
                echo "provenance attempt=\$attempt failed"
                if (( \$attempt >= \$max_attempts )); then
                  exit 1
                fi
                attempt=\$(( \$attempt + 1 ))
                sleep 30
              done
              echo "provenance attempt=\$attempt passed"
              mkdir -v -p ${artifacts_local_dir}/scs/${it.target}
              cp ${it.target}.json ${artifacts_local_dir}/scs/${it.target}/provenance.json
            """
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
          def outdir = "${artifacts_local_dir}/scs/${it.target}"
          sh """
            mkdir -v -p ${outdir}
            sbomnix ${artifacts_local_dir}/${it.target} \
              --csv ${outdir}/sbom.csv \
              --cdx ${outdir}/sbom.cdx.json \
              --spdx ${outdir}/sbom.spdx.json
          """
        }
      }
      // Signing stages
      // Skip signing stages in vm and dbg environments, where NetHSM is not available
      if (env.CI_ENV != 'vm' && env.CI_ENV != 'dbg') {
        if (!it.no_image) {
          stage("Sign image ${shortname}") {
            def img_path = get_img_path(it.target, artifacts_local_dir)
            sh """
              mkdir -v -p "\$(dirname "${artifacts_local_dir}/scs/${img_path}")"
            """
            lock('signing') {
              sh """
                openssl dgst -sha256 -sign \
                  "pkcs11:token=${signingToken};object=GhafInfraSignECP256" \
                  -out ${artifacts_local_dir}/scs/${img_path}.sig \
                  ${artifacts_local_dir}/${img_path}
              """
            }
          }
        }
        if (it.get('provenance', true)) {
          stage("Sign provenance ${shortname}") {
            lock('signing') {
              sh """
                openssl pkeyutl -sign -rawin \
                  -inkey "pkcs11:token=${signingToken};object=GhafInfraSignProv" \
                  -out ${artifacts_local_dir}/scs/${it.target}/provenance.json.sig \
                  -in ${artifacts_local_dir}/scs/${it.target}/provenance.json
              """
            }
          }
        }
        if (it.get('uefisign', false) || it.get('uefisigniso', false)) {
          stage("Sign UEFI ${shortname}") {
            def diskPath = artifacts_local_dir + "/" + get_img_path(it.target, artifacts_local_dir)
            def outdir = run_cmd("dirname '${diskPath}' | sed 's/${it.target}/uefisigned\\/${it.target}/'")
            sh "mkdir -v -p ${outdir}"

            def signer = "uefisign"
            if (it.target.contains("nvidia-jetson-orin")) {
              signer = "uefisign-simple"
            }

            def keydir = "keys"
            def keysLocation = "${artifacts_local_dir}/uefisigned"
            def keysPath = "${keysLocation}/${keydir}"

            lock('signing') {
              sh "${signer} /etc/jenkins/keys/secboot/DB.pem 'pkcs11:token=${signingToken};object=uefi-ghaf-db' '${diskPath}' ${outdir}"

              // needs to be locked as well to prevent race conditions in shared directory
              if (!fileExists("${keysPath}.tar")) {
                sh """
                  cp -r -L /etc/jenkins/keys/secboot ${keysPath}
                  chmod +w ${keysPath}
                  cp -L /etc/jenkins/enroll-secureboot-keys.sh ${keysPath}/enroll.sh
                  tar -cvf ${keysPath}.tar -C ${keysLocation} ${keydir}
                """
              }
            }
          }
        }
      }
      // Link artifacts
      stage("Link artifacts ${shortname}") {
        if (!currentBuild.description || !currentBuild.description.contains(artifacts_href)) {
          append_to_build_description(artifacts_href)
        }
      }
      // Test
      if (it.testset != null && !it.testset.isEmpty()) {
        stage("Test ${shortname}") {
          def img_path = get_img_path(it.target, artifacts_local_dir)
          def img_url = "${env.JENKINS_URL}/${artifacts}/${img_path}"
          run_hw_tests(it.target, img_url, testagent_host, it.testset, artifacts_local_dir)
        }
        if (it.uefitest) {
          stage("Test Signed ${shortname}") {
            def img_path = get_img_path(it.target, "${artifacts_local_dir}/uefisigned")
            def img_url = "${env.JENKINS_URL}/${artifacts}/uefisigned/${img_path}"
            run_hw_tests("uefisigned/${it.target}", img_url, testagent_host, it.testset, artifacts_local_dir, false)
          }
        }
      }
    }
  }
  return pipeline
}

def run_hw_tests(String target, String img_url, String testagent_host, String testset, String results_location, Boolean verify=true) {
  def shortname = target.substring(target.lastIndexOf('.') + 1)
  def build_href = "<a href=\"${env.BUILD_URL}\">${env.JOB_NAME}#${env.BUILD_ID}</a>"
  def desc = "Triggered by ${build_href}<br>(${target})"
  def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
    parameters: [
      string(name: "IMG_URL", value: img_url),
      string(name: "TESTSET", value: testset),
      string(name: "DESC", value: desc),
      string(name: "TESTAGENT_HOST", value: testagent_host),
      booleanParam(name: "VERIFY", value: verify),
      booleanParam(name: "USE_FLAKE_PINNED_CI_TEST", value: env.CI_ENV == "release"),
      booleanParam(name: "RELOAD_ONLY", value: false),
    ],
  )
  println("ghaf-hw-test log '${target}:")
  sh "cat /var/lib/jenkins/jobs/ghaf-hw-test/builds/${job.number}/log | sed 's/^/    /'"
  if (job.result != "SUCCESS") {
    unstable("FAILED: ${target} ${testset}")
    currentBuild.result = "FAILURE"
    def test_href = "<a href=\"${job.absoluteUrl}\">⛔ ${shortname}</a>"
    append_to_build_description(test_href)
  }
  copyArtifacts(
    projectName: "ghaf-hw-test",
    selector: specific("${job.number}"),
    target: "${results_location}/test-results/${target}",
    optional: true,
  )
}

def get_img_path(String target, String in_path) {
  def img_path = run_cmd("find -L ${in_path}/${target} -regex '.*\\.\\(img\\|raw\\|zst\\|iso\\)\$' -print -quit")
  if (!img_path) {
    error("No image found for target '${target}'")
  }
  // Return img_path relative to 'in_path'
  return img_path - "${in_path}/"
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
