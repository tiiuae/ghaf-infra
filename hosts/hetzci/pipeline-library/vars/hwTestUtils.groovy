// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def get_test_conf_property(String file_path, String device, String property) {
  def device_data = readJSON file: file_path
  def property_data = "${device_data['addresses'][device][property]}"
  println "Got device '${device}' property '${property}' value: '${property_data}'"
  return property_data
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
def resolve_test_target(String explicitTestTarget = null, String buildTarget = null, String fallbackTarget = null) {
  def explicit = explicitTestTarget?.trim()
  if (explicit) {
    return explicit
  }
  def build = buildTarget?.trim()
  if (build) {
    return build
  }
  def fallback = fallbackTarget?.trim()
  return fallback ?: null
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
  artifactUtils.archive_robot_artifacts(tmp_img_dir, should_archive)
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

def run_hw_test(
  String buildShortname,
  String testTargetName,
  String testIdentity,
  String testset,
  String testagent_host,
  Map oci_result,
  boolean secureboot,
  String ci_env) {
  // Keep the blocking downstream wait outside node('built-in') so ghaf-hw-test
  // can acquire a controller executor for its own initialization stages.
  def build_href = "<a href=\"${utils.html_escape(env.BUILD_URL)}\">" +
    "${utils.html_escape("${env.JOB_NAME}#${env.BUILD_ID}")}</a>"
  def normalizedTestTarget = testTargetName?.trim()
  def normalizedTestIdentity = testIdentity?.trim()
  def desc = normalizedTestIdentity ?
    "Triggered by ${build_href}<br>(${utils.html_escape(normalizedTestIdentity)})" :
    "Triggered by ${build_href}<br>(${utils.html_escape(buildShortname)})"
  def test_params = [
    string(name: "TESTSET", value: testset),
    string(name: "DESC", value: desc),
    string(name: "TESTAGENT_HOST", value: testagent_host ?: ''),
    booleanParam(name: "USE_FLAKE_PINNED_CI_TEST", value: ci_env == "release"),
    booleanParam(name: "RELOAD_ONLY", value: false),
    booleanParam(name: "SECUREBOOT", value: secureboot),
  ]
  if (oci_result == null) {
    error("Missing OCI publish result for ${buildShortname}; cannot trigger ghaf-hw-test")
  }
  test_params += [
    string(name: "OCI_IMAGE_REF", value: oci_result.primary.reference),
  ]
  if (normalizedTestTarget) {
    test_params += [
      string(name: "TEST_TARGET", value: normalizedTestTarget),
    ]
  }
  def job = build(job: "ghaf-hw-test", propagate: false, wait: true,
    parameters: test_params
  )
  return [
    url: job.absoluteUrl,
    number: job.number,
    result: job.result,
  ]
}

def collect_hw_test_result(
  String testIdentity,
  String testPathKey,
  boolean secureboot,
  String output,
  Map job) {
  def logPrefix = secureboot ? "ghaf-hw-test log SB '${testIdentity}:" : "ghaf-hw-test log '${testIdentity}:"
  println(logPrefix)
  sh "cat /var/lib/jenkins/jobs/ghaf-hw-test/builds/${job.number}/log | sed 's/^/    /'"
  if (job.result != "SUCCESS") {
    unstable("FAILED: ${testIdentity}")
    currentBuild.result = "FAILURE"
    utils.append_to_build_description(
      "<a href=\"${utils.html_escape(job.url)}\">⛔ ${utils.html_escape(testIdentity)}</a>"
    )
  }
  def artifactsTarget = "${output}/test-results/${testPathKey}"
  copyArtifacts(
    projectName: "ghaf-hw-test",
    selector: specific("${job.number}"),
    target: artifactsTarget,
    optional: true
  )
}
