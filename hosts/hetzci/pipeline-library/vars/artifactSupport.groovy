// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

import java.util.regex.Pattern

private def shell_quote(String value) {
  if (value == null) {
    return "''"
  }
  return "'${value.replace("'", "'\"'\"'")}'"
}

def run_wget(String url, String to_dir) {
  def quotedDir = shell_quote(to_dir)
  def quotedUrl = shell_quote(url)
  def output = sh(
    script: """
      bash -o pipefail -c "
        wget --show-progress --progress=dot:giga --force-directories --timestamping \
          -P ${quotedDir} ${quotedUrl} 2>&1 | tee /dev/stderr
      "
    """.stripIndent().trim(),
    returnStdout: true
  ).trim()
  // wget prints the saved path inside curly quotes, so straight apostrophes
  // remain valid filename characters and must not terminate the match.
  def matcher = output =~ /(${Pattern.quote(to_dir)}[^’\r\n]+)/
  if (matcher.find()) {
    return matcher.group(1)
  }
  error("Failed to determine downloaded file path for '${url}'")
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
  return basename.endsWith('.iso') ? 'installer' : 'disk'
}

def append_to_build_description(String text, boolean once = false) {
  lock('build-description') {
    if (once && currentBuild.description?.contains(text)) {
      return
    }
    if (!currentBuild.description) {
      currentBuild.description = text
    } else {
      currentBuild.description = "${currentBuild.description}<br>${text}"
    }
  }
}

def controller_workdir() {
  def rawTag = env.BUILD_TAG ?: "${env.JOB_NAME}-${env.BUILD_NUMBER}"
  def tag = pipelineModel.safe_path_component(rawTag)
  if (!tag || tag == 'null-null') {
    error('Cannot derive a unique controller workdir for this build')
  }
  return "/var/lib/jenkins/ghaf-pipeline-workspaces/${tag}"
}

def build_tmpdir(String name) {
  def component = pipelineModel.safe_path_component(name)
  if (!component || component == 'null') {
    error("Cannot derive a unique build tmpdir for '${name}'")
  }
  return "${controller_workdir()}/tmp/${component}"
}

def with_controller_workspace(String workspace, Closure body) {
  node('built-in') {
    dir(workspace) {
      body()
    }
  }
}
