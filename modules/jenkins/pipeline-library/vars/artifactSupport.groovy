// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

import java.util.regex.Pattern

def shell_quote(String value) {
  if (value == null) {
    return "''"
  }
  return "'${value.replace("'", "'\"'\"'")}'"
}

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout: true).trim()
}

def oci_annotations(String reference) {
  return readJSON(
    text: run_cmd("oras manifest fetch --format json '${reference}'")
  ).content?.annotations ?: [:]
}

def oras_pull_json(String reference, String outputDir) {
  return readJSON(
    text: run_cmd("oras pull --format json -o '${outputDir}' '${reference}'")
  )
}

def fetch_build_manifest(String reference, String outputDir) {
  def ociManifest = readJSON(text: run_cmd("oras manifest fetch --format json ${shell_quote(reference)}")).content
  def descriptor = ([ociManifest.config] + (ociManifest.layers ?: [])).find {
    it?.mediaType in ['application/vnd.ghaf.manifest.v2+json', 'application/vnd.ghaf.manifest.v1+json']
  }
  if (!descriptor?.digest) error("Unable to find build manifest in '${reference}'")
  def path = "${outputDir}/manifest.json"
  def blob = "${parse_oci_reference(reference).repository}@${descriptor.digest}"
  sh "mkdir -p ${shell_quote(outputDir)}"
  sh "oras blob fetch --output ${shell_quote(path)} ${shell_quote(blob)}"
  return path
}

def main_image(Map manifest, String requestedPath = null) {
  if (manifest.images == null && manifest.image) return manifest.image
  def images = manifest.images ?: []
  def matches = requestedPath ? images.findAll { it.path == requestedPath } : images
  if (matches.size() != 1) {
    error("Legacy build manifest must identify one image to flash; found ${matches.size()} matching images")
  }
  return matches[0]
}

def downloaded_file(String directory, String path) {
  if (!path || path.startsWith('/') || path.tokenize('/').contains('..')) {
    error("Artifact path must be relative and stay within the download directory: '${path}'")
  }
  def file = "${directory}/${path}"
  if (sh(script: """
    root=\$(realpath -e -- ${shell_quote(directory)}) || exit 1
    file=\$(realpath -e -- ${shell_quote(file)}) || exit 1
    case "\$file" in
      "\$root"/*) test -f "\$file" ;;
      *) exit 1 ;;
    esac
  """, returnStatus: true) != 0) {
    error("Artifact must be a regular file within the download directory: '${path}'")
  }
  return file
}

@NonCPS
def find_oci_pull_file(Map pullResult, String mediaType) {
  def file = pullResult.files?.find { it.mediaType == mediaType }
  return file?.path
}

@NonCPS
def parse_oci_reference(String reference) {
  def digestSeparator = reference.indexOf('@')
  if (digestSeparator >= 0) {
    return [
      repository: reference.substring(0, digestSeparator),
      tag: null,
      digest: reference.substring(digestSeparator + 1),
    ]
  }

  def tagSeparator = reference.lastIndexOf(':')
  def lastSlash = reference.lastIndexOf('/')
  if (tagSeparator > lastSlash) {
    return [
      repository: reference.substring(0, tagSeparator),
      tag: reference.substring(tagSeparator + 1),
      digest: null,
    ]
  }

  return [
    repository: reference,
    tag: null,
    digest: null,
  ]
}

def run_wget(String url, String to_dir) {
  def quotedDir = shell_quote(to_dir)
  def quotedUrl = shell_quote(url)
  def command = "wget --show-progress --progress=dot:giga --force-directories --timestamping " +
    "-P ${quotedDir} ${quotedUrl} 2>&1 | tee /dev/stderr"
  def output = sh(
    script: "bash -o pipefail -c ${shell_quote(command)}",
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

def path_basename(String path) {
  if (path == null) {
    return null
  }
  def idx = path.lastIndexOf('/')
  return idx >= 0 ? path.substring(idx + 1) : path
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

def clean_controller_workdir() {
  node('built-in') {
    sh "rm -rf '${controller_workdir()}'"
  }
}
