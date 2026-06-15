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

def orin_artifact_root_urls(String artifactsUrl) {
  def base = artifactsUrl?.trim()?.replaceAll('/+$', '')
  if (!base) {
    error("Missing Orin artifacts URL")
  }
  return [
    root_url: base,
    signed_artifacts_url: "${base}/signed-output",
    manifest_url: "${base}/signed-output/flash-manifest.json",
    provenance_url: "${base}/attestations/provenance.json",
    provenance_signature_url: "${base}/attestations/provenance.json.sig",
  ]
}

@NonCPS
def flash_manifest_artifact(Map flashManifest, String role) {
  return flashManifest?.artifacts?.find { it.role == role }
}

def download_orin_artifact_root_flash_set(String artifactsUrl, String outputDir) {
  def urls = orin_artifact_root_urls(artifactsUrl)
  def manifestPath = run_wget(urls.manifest_url, outputDir)
  def flashManifest = readJSON file: manifestPath, returnPojo: true
  def transport = flashManifest?.transport ?: ''
  if (transport != 'initrd-mass-storage') {
    error("Unsupported Orin flash transport '${transport}' for Orin artifact-root flashing")
  }
  def flasher = flashManifest?.flasher ?: [:]
  def flasherEntrypoint = flasher.entrypoint?.trim()
  if (!flasherEntrypoint) {
    error("Missing flasher entrypoint in Orin flash manifest '${manifestPath}'")
  }
  if (!(flasherEntrypoint ==~ /bin\/initrd-flash-[A-Za-z0-9._-]+/)) {
    error("Unsupported flasher entrypoint '${flasherEntrypoint}' in Orin flash manifest '${manifestPath}'")
  }
  def espArtifact = flash_manifest_artifact(flashManifest, 'esp')
  def rootArtifact = flash_manifest_artifact(flashManifest, 'root')
  if (!espArtifact?.name || !rootArtifact?.name) {
    error("Expected Orin flash manifest '${manifestPath}' to define both esp and root artifacts")
  }

  def manifestDirIdx = manifestPath.lastIndexOf('/')
  def flashImagesDir = manifestDirIdx > 0 ? manifestPath.substring(0, manifestDirIdx) : '.'
  def espPath = run_wget("${urls.signed_artifacts_url}/${espArtifact.name}", outputDir)
  def rootPath = run_wget("${urls.signed_artifacts_url}/${rootArtifact.name}", outputDir)
  def espSigPath = run_wget("${urls.root_url}/${espArtifact.name}.sig", outputDir)
  def rootSigPath = run_wget("${urls.root_url}/${rootArtifact.name}.sig", outputDir)

  return [
    manifest: flashManifest,
    manifest_path: manifestPath,
    flash_images_dir: flashImagesDir,
    transport: transport,
    flasher_entrypoint: flasherEntrypoint,
    flash_target_drives: flasher.target_drives ?: [],
    esp_path: espPath,
    root_path: rootPath,
    esp_signature_path: espSigPath,
    root_signature_path: rootSigPath,
    provenance_url: urls.provenance_url,
    provenance_signature_url: urls.provenance_signature_url,
  ]
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

def clean_controller_workdir() {
  node('built-in') {
    sh "rm -rf '${controller_workdir()}'"
  }
}
