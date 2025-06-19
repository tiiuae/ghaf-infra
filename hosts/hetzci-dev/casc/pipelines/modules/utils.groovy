#!/usr/bin/env groovy

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout:true).trim()
}

def create_pipeline(List<Map> targets) {
  def pipeline = [:]
  def stamp = run_cmd('date +"%Y%m%d_%H%M%S"')
  def commit = run_cmd('git rev-parse HEAD')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${commit}"
  def artifacts_local_dir = "/var/lib/jenkins/${artifacts}"
  def artifacts_href = "<a href=\"/${artifacts}\">📦 Artifacts</a>"
  currentBuild.description = "${artifacts_href}"
  sh "mkdir -p ${artifacts_local_dir}"
  // Evaluate
  stage("Eval") {
    lock('evaluator') {
      sh 'nix flake show --all-systems | ansi2txt'
    }
  }
  targets.each {
    def shortname = it.target.substring(it.target.lastIndexOf('.') + 1)
    pipeline["${it.target}"] = {
      // Build
      stage("Build ${shortname}") {
        sh "nix build -v .#${it.target} --out-link ${it.target}"
      }
      // Archive
      stage("Archive ${shortname}") {
        sh "cp -P ${it.target} ${artifacts_local_dir}/"
      }
      // Test
      if (it.testset != null) {
        stage("Test ${shortname}") {
          def img_path = run_cmd("find -L ${it.target} -regex '.*\\.\\(img\\|raw\\|zst\\|iso\\)\$' -print -quit")
          if (!img_path) {
            error("No image found for target '${it.target}'")
          }
          def img_url = "${env.JENKINS_URL}/${artifacts}/${img_path}"
          def build_href = "<a href=\"${env.BUILD_URL}\">${env.JOB_NAME}#${env.BUILD_ID}</a>"
          def desc = "Triggered by ${build_href}<br>(${it.target})"
          def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
            parameters: [
              string(name: "IMG_URL", value: img_url),
              string(name: "TESTSET", value: it.testset),
              string(name: "DESC", value: desc),
              booleanParam(name: "RELOAD_ONLY", value: false),
            ],
          )
          if (job.result != "SUCCESS") {
            unstable("FAILED: ${it.target} ${it.testset}")
            currentBuild.result = "FAILURE"
            def test_href = "<a href=\"${job.absoluteUrl}\">⛔ ${shortname}</a>"
            currentBuild.description = "${currentBuild.description}<br>${test_href}"
          }
          copyArtifacts(
            projectName: "ghaf-hw-test",
            selector: specific("${job.number}"),
            target: "${artifacts_local_dir}/test-results/${it.target}",
          )
        }
      }
    }
  }
  return pipeline
}

return this
