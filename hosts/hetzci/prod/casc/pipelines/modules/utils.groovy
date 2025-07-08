#!/usr/bin/env groovy

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout:true).trim()
}

def append_to_build_description(String text) {
  if(!currentBuild.description) {
    currentBuild.description = text
  } else {
    currentBuild.description = "${currentBuild.description}<br>${text}"
  }
}

def create_pipeline(List<Map> targets) {
  def pipeline = [:]
  def stamp = run_cmd('date +"%Y%m%d_%H%M%S%3N"')
  def commit = run_cmd('git rev-parse HEAD')
  def artifacts = "artifacts/${env.JOB_BASE_NAME}/${stamp}-commit_${commit}"
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
    pipeline["${it.target}"] = {
      // Build
      stage("Build ${shortname}") {
        sh "nix build -v .#${it.target} --out-link ${it.target}"
      }
      // Archive
      stage("Archive ${shortname}") {
        sh "mkdir -v -p ${artifacts_local_dir} && cp -P ${it.target} ${artifacts_local_dir}/"
        if (!currentBuild.description.contains(artifacts_href)) {
          append_to_build_description(artifacts_href)
        }
      }
      // Test
      if (it.testset != null && !it.testset.isEmpty()) {
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
            append_to_build_description(test_href)
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
