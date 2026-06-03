// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def run_cmd(String cmd) {
  return sh(script: cmd, returnStdout: true).trim()
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

def clean_controller_workdir() {
  node('built-in') {
    sh "rm -rf '${artifactSupport.controller_workdir()}'"
  }
}
