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
        sh "echo ${artifacts_local_dir} >./artifacts_dir"
      }
      // Provenance
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
          'PROVENANCE_BUILD_TYPE="https://github.com/tiiuae/ghaf-infra/blob/ea938e90/slsa/v1.0/L1/buildtype.md"',
          "PROVENANCE_BUILDER_ID=${env.JENKINS_URL}",
          "PROVENANCE_INVOCATION_ID=${env.BUILD_URL}",
          "PROVENANCE_TIMESTAMP_BEGIN=${build_beg}",
          "PROVENANCE_TIMESTAMP_FINISHED=${build_end}",
          "PROVENANCE_EXTERNAL_PARAMS=${ext_params}"
        ]) {
          catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            sh """
              attempt=1; max_attempts=5;
              while ! provenance  ${artifacts_local_dir}/${it.target}/ --recursive --out ${it.target}.json; do
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
      // Signing stages
      // Skip signing stages in vm environment, where NetHSM is not available
      if (env.CI_ENV != 'vm') {
        if (!it.no_image) {
          stage("Sign image ${shortname}") {
            catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
              def img_path = get_img_path(it.target, artifacts_local_dir)
              sh """
                mkdir -v -p "\$(dirname "${artifacts_local_dir}/scs/${img_path}")"
              """
              lock('signing') {
                sh """
                  openssl dgst -sha256 -sign \
                    "pkcs11:token=NetHSM;object=GhafInfraSignECP256" \
                    -out ${artifacts_local_dir}/scs/${img_path}.sig \
                    ${artifacts_local_dir}/${img_path}
                """
              }
            }
          }
        }
        stage("Sign provenance ${shortname}") {
          catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
            lock('signing') {
              sh """
                openssl pkeyutl -sign -rawin \
                  -inkey "pkcs11:token=NetHSM;object=GhafInfraSignProv" \
                  -out ${artifacts_local_dir}/scs/${it.target}/provenance.json.sig \
                  -in ${artifacts_local_dir}/scs/${it.target}/provenance.json
              """
            }
          }
        }
        if (it.get('uefisign', false) || it.get('uefisigniso', false)) {
          stage("Sign UEFI ${shortname}") {
            def binary = it.get('uefisigniso', false) ? "uefisigniso" : "uefisign"
            def imageName = it.get('uefisigniso', false) ? "ghaf.iso" : "disk1.raw.zst"

            def diskPath  = run_cmd("find -L ${artifacts_local_dir}/${it.target} -type f -name '${imageName}' -print -quit")
            if (!diskPath) {
              error("No ${imageName} found for '${it.target}'")
            }

            def outdir = "${artifacts_local_dir}/uefisigned/${it.target}-signed"
            sh "mkdir -v -p ${outdir}"

            lock('signing') {
              sh "${binary} /etc/jenkins/keys/db.pem 'pkcs11:token=NetHSM;object=tempDBkey' '${diskPath}' ${outdir}"
            }

            // distribute certs with artifacts, in both pem and der formats
            sh """
              cp -r /etc/jenkins/keys ${outdir}/
              openssl x509 -in ${outdir}/keys/db.pem -outform DER -out ${outdir}/keys/db.der
              openssl x509 -in ${outdir}/keys/pk.pem -outform DER -out ${outdir}/keys/pk.der
              openssl x509 -in ${outdir}/keys/kek.pem -outform DER -out ${outdir}/keys/kek.der
            """
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
          def build_href = "<a href=\"${env.BUILD_URL}\">${env.JOB_NAME}#${env.BUILD_ID}</a>"
          def desc = "Triggered by ${build_href}<br>(${it.target})"
          def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
            parameters: [
              string(name: "IMG_URL", value: img_url),
              string(name: "TESTSET", value: it.testset),
              string(name: "DESC", value: desc),
              string(name: "TESTAGENT_HOST", value: testagent_host),
              booleanParam(name: "RELOAD_ONLY", value: false),
            ],
          )
          println("ghaf-hw-test log '${it.target}':")
          sh "cat /var/lib/jenkins/jobs/ghaf-hw-test/builds/${job.number}/log | sed 's/^/    /'"
          if (job.result != "SUCCESS") {
            unstable("FAILED: ${it.target} ${it.testset}")
            currentBuild.result = "FAILURE"
            def test_href = "<a href=\"${job.absoluteUrl}\">⛔ ${shortname}</a>"
            append_to_build_description(test_href)
          }
          copyArtifacts(
            projectName: "ghaf-hw-test",
            selector: specific("${job.number}"),
            target: "${artifacts_local_dir}/test-results/${it.target}",
            optional: true,
          )
        }
      }
    }
  }
  return pipeline
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
