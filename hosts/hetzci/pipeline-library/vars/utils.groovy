// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def run_cmd(String cmd) {
  artifactUtils.run_cmd(cmd)
}

def run_wget(String url, String to_dir) {
  artifactUtils.run_wget(url, to_dir)
}

def checkout_ci_test_sources(
  String pinned_source_file,
  boolean use_flake_pinned_ci_test,
  String ci_test_repo_branch,
  String ci_test_repo_url) {
  checkoutUtils.checkout_ci_test_sources(
    pinned_source_file,
    use_flake_pinned_ci_test,
    ci_test_repo_branch,
    ci_test_repo_url
  )
}

def checkout_remote_ref(String repoUrl, String requestedRef, boolean allowSyntheticRefs = false) {
  checkoutUtils.checkout_remote_ref(repoUrl, requestedRef, allowSyntheticRefs)
}

def checkout_github_pr_merge(String repoUrl, String prNumber, String targetBranch = null, List extraExtensions = []) {
  checkoutUtils.checkout_github_pr_merge(repoUrl, prNumber, targetBranch, extraExtensions)
}

def pipeline_model_call(Closure body) {
  try {
    return body()
  } catch (IllegalArgumentException e) {
    error(e.message)
  }
}

def short_target_name(String targetName) {
  pipeline_model_call { pipelineModel.short_target_name(targetName) }
}

def path_basename(String path) {
  artifactUtils.path_basename(path)
}

def html_escape(String value) {
  pipeline_model_call { pipelineModel.html_escape(value) }
}

def image_role(String path) {
  artifactUtils.image_role(path)
}

def append_to_build_description(String text) {
  artifactUtils.append_to_build_description(text)
}

def append_to_build_description_once(String text) {
  artifactUtils.append_to_build_description_once(text)
}

def hw_test_stage_display_name(String buildShortname, List<Map> testRuns) {
  pipelineExecution.hw_test_stage_display_name(buildShortname, testRuns)
}

def ghaf_flake_ref(String repo, String rev) {
  pipelineExecution.ghaf_flake_ref(repo, rev)
}

@NonCPS
// Why NonCPS? Jenkins CPS does not handle regex matchers reliably.
// See: https://stackoverflow.com/a/48465528
def derive_target_name(String imgUrl, String ociTarget) {
  hwTestUtils.derive_target_name(imgUrl, ociTarget)
}

@NonCPS
def resolve_test_target(String explicitTestTarget = null, String buildTarget = null, String fallbackTarget = null) {
  hwTestUtils.resolve_test_target(explicitTestTarget, buildTarget, fallbackTarget)
}

@NonCPS
def derive_device_info(String target, boolean secureboot) {
  hwTestUtils.derive_device_info(target, secureboot)
}

@NonCPS
def device_name_from_tag(String deviceTag) {
  hwTestUtils.device_name_from_tag(deviceTag)
}

def extra_tag_suffix(String target, String deviceTag) {
  hwTestUtils.extra_tag_suffix(target, deviceTag)
}

def boot_tag_for(String deviceTag) {
  hwTestUtils.boot_tag_for(deviceTag)
}

def archive_robot_artifacts(String tmp_img_dir, boolean should_archive) {
  artifactUtils.archive_robot_artifacts(tmp_img_dir, should_archive)
}

def setup_mount_commands(String conf_file_path, String target, String device_name) {
  hwTestUtils.setup_mount_commands(conf_file_path, target, device_name)
}

def resolve_flash_target(String conf_file_path, String device_name, String mount_cmd, String unmount_cmd) {
  hwTestUtils.resolve_flash_target(conf_file_path, device_name, mount_cmd, unmount_cmd)
}

def assert_flash_target_unmounted(String dev) {
  hwTestUtils.assert_flash_target_unmounted(dev)
}

def withRedundancyRouter(String object, Closure body) {
  pipelineExecution.withRedundancyRouter(object, body)
}

@NonCPS
// Why NonCPS? Jenkins CPS does not handle regex matchers reliably.
// See: https://stackoverflow.com/a/48465528
def resolve_ghaf_flake_ref(String explicitFlakeRef, String imgUrl, String ociFlakeRef) {
  hwTestUtils.resolve_ghaf_flake_ref(explicitFlakeRef, imgUrl, ociFlakeRef)
}

@NonCPS
def safe_path_component(String value) {
  pipelineModel.safe_path_component(value)
}

def safe_stage_key(String value) {
  pipelineModel.safe_stage_key(value)
}

def normalize_optional_string(value) {
  pipelineModel.normalize_optional_string(value)
}

def test_identity(Map testConfig, boolean secureboot = false) {
  pipeline_model_call { pipelineModel.test_identity(testConfig, secureboot) }
}

def normalize_tests(Map buildConfig, String defaultTestagentHost = null) {
  pipeline_model_call { pipelineModel.normalize_tests(buildConfig, defaultTestagentHost) }
}

def normalize_build_config(
  Map targetConfig,
  boolean signingPossible,
  String ciEnv,
  String defaultTestagentHost = null,
  boolean allowExplicitTests = true) {
  pipeline_model_call {
    pipelineModel.normalize_build_config(
      targetConfig,
      signingPossible,
      ciEnv,
      defaultTestagentHost,
      allowExplicitTests
    )
  }
}

def test_result_entry(Map testRun, Map result = [:]) {
  pipeline_model_call { pipelineModel.test_result_entry(testRun, result) }
}

def controller_workdir() {
  artifactUtils.controller_workdir()
}

def build_tmpdir(String name) {
  artifactUtils.build_tmpdir(name)
}

def clean_controller_workdir() {
  artifactUtils.clean_controller_workdir()
}

def with_controller_workspace(String workspace, Closure body) {
  artifactUtils.with_controller_workspace(workspace, body)
}

def run_hw_test(
  String buildShortname,
  String testTargetName,
  String testIdentity,
  String testset,
  String testagent_host,
  Map oci_result,
  boolean secureboot,
  String ci_env) {
  hwTestUtils.run_hw_test(
    buildShortname,
    testTargetName,
    testIdentity,
    testset,
    testagent_host,
    oci_result,
    secureboot,
    ci_env
  )
}

def collect_hw_test_result(
  String testIdentity,
  String testPathKey,
  boolean secureboot,
  String output,
  Map job) {
  hwTestUtils.collect_hw_test_result(
    testIdentity,
    testPathKey,
    secureboot,
    output,
    job
  )
}

def create_pipeline(
  List<Map> targets,
  String testagent_host = null,
  String target_flake_ref = null,
  Map options = [:]) {
  pipelineExecution.create_pipeline(targets, testagent_host, target_flake_ref, options)
}

def set_github_commit_status(
  String message,
  String state,
  String commit,
  String project = "tiiuae/ghaf",
  String context = "jenkins-pre-merge") {
  pipelineExecution.set_github_commit_status(message, state, commit, project, context)
}
