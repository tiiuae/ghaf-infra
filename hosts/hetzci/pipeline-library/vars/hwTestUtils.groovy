// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

private def get_test_conf_property(String file_path, String device, String property) {
  def device_data = readJSON file: file_path
  def property_data = "${device_data['addresses'][device][property]}"
  println "Got device '${device}' property '${property}' value: '${property_data}'"
  return property_data
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

def is_orin_artifact_root_mode(String testTarget, String buildTarget, String imgUrl, String ociImageRef) {
  if (ociImageRef?.trim() || !imgUrl?.trim()) {
    return false
  }
  if (imgUrl.trim() ==~ /.*\.(img|raw|zst|iso)$/) {
    return false
  }
  return buildTarget?.trim()?.contains('nvidia-jetson-orin') || testTarget?.trim()?.contains('nvidia-jetson-orin')
}

@NonCPS
def orin_flash_script_attr(String buildTarget) {
  def normalizedTarget = buildTarget?.trim()
  if (!normalizedTarget?.contains('nvidia-jetson-orin')) {
    throw new IllegalArgumentException("Cannot derive Orin flash-script attribute from target '${buildTarget}'")
  }
  def rewrittenTarget = normalizedTarget.replaceFirst(/^packages\.[^.]+\./, '')
  return "packages.x86_64-linux.${rewrittenTarget}-flash-script"
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

private def wrapped_usb_switch(String command) {
  return "(${command}; rc=\$?; /run/wrappers/bin/sudo udevadm settle --timeout=10 || true; sleep 2; exit \$rc)"
}

def setup_mount_commands(String conf_file_path, String target, String device_name) {
  if (target.contains("microchip-icicle-")) {
    def muxport = get_test_conf_property(conf_file_path, device_name, 'usb_sd_mux_port')
    return [
      mount_cmd: wrapped_usb_switch("/run/wrappers/bin/sudo usbsdmux ${muxport} host"),
      unmount_cmd: wrapped_usb_switch("/run/wrappers/bin/sudo usbsdmux ${muxport} dut"),
    ]
  }
  def serial = get_test_conf_property(conf_file_path, device_name, 'usbhub_serial')
  return [
    mount_cmd: wrapped_usb_switch("/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}"),
    unmount_cmd: wrapped_usb_switch("/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}"),
  ]
}

def resolve_flash_target(String conf_file_path, String device_name, String mount_cmd, String unmount_cmd) {
  def dev = get_test_conf_property(conf_file_path, device_name, 'ext_drive_by-id')
  println "Checking that flash target '${dev}' is connected..."
  sh """
    if /run/wrappers/bin/sudo test -f ${dev}; then
      echo "dev ${dev} found as regular file, removing the file and trying re-mount"
      /run/wrappers/bin/sudo rm ${dev}
    fi

    for attempt in \$(seq 1 3); do
      echo "Connecting target USB disk to test agent, attempt \${attempt}/3..."
      if ${mount_cmd}; then
        for wait_round in \$(seq 1 45); do
          /run/wrappers/bin/sudo udevadm settle --timeout=2 || true
          if /run/wrappers/bin/sudo test -L ${dev}; then
            echo "Symlink ${dev} found."
            exit 0
          fi
          sleep 2
        done

        echo "Symlink ${dev} not found after attempt \${attempt}."
      else
        mount_status=\$?
        echo "Connecting target USB disk command failed with exit status \${mount_status}."
      fi

      if [ "\${attempt}" -lt 3 ]; then
        echo "Toggling USB hub back to target before retry."
        if ! ${unmount_cmd}; then
          echo "Failed to toggle USB hub back to target; continuing to next connect attempt."
        fi
      fi
    done

    echo "Symlink ${dev} not found. Failed to connect target USB disk to test agent."
    echo "Check USB cables. Maybe need to reboot test agent or Acroname USB hub."
    echo "Block devices visible on test agent:"
    lsblk -S -o NAME,TRAN,SERIAL,MODEL,SIZE,STATE || true
    echo "Recent USB/storage kernel messages:"
    /run/wrappers/bin/sudo dmesg -T | tail -n 80 | sed 's/^/  /' || true
    echo "Aborting flashing ${device_name}"
    exit 1
  """
  return dev
}

def assert_flash_target_unmounted(String dev) {
  println "Checking that flash target '${dev}' is disconnected from the test agent..."
  sh """
    for wait_round in \$(seq 1 45); do
      /run/wrappers/bin/sudo udevadm settle --timeout=2 || true
      if ! /run/wrappers/bin/sudo test -L ${dev}; then
        echo "Symlink ${dev} removed."
        exit 0
      fi
      sleep 2
    done

    echo "Symlink ${dev} was found. Failed to unmount target USB disk from test agent."
    echo "Resolved target: \$(/run/wrappers/bin/sudo readlink -f ${dev} || true)"
    exit 1
  """
}

@NonCPS
// Why NonCPS? Jenkins CPS does not handle regex matchers reliably.
// See: https://stackoverflow.com/a/48465528
def resolve_ghaf_flake_ref(String explicitFlakeRef, String imgUrl, String ociFlakeRef) {
  def normalizedFlakeRef = explicitFlakeRef?.trim() ?: ociFlakeRef?.trim()
  if (normalizedFlakeRef) {
    return normalizedFlakeRef
  }
  def match = imgUrl =~ /commit_([a-f0-9]{40})/
  if (match) {
    return "git+https://github.com/tiiuae/ghaf?rev=${match[0][1]}"
  }
  return null
}

def prepare_orin_artifact_root_flash(
  String imgUrl,
  String outputDir,
  String buildTarget,
  String testTarget,
  String requestedDrive = null
) {
  def flashSet = artifactSupport.download_orin_artifact_root_flash_set(imgUrl, outputDir)
  def orinTarget = buildTarget?.trim() ?: testTarget?.trim()
  def targetDrive = requestedDrive?.trim() ?: 'usb'
  def supportedDrives = flashSet.flash_target_drives ?: []
  if (supportedDrives && !supportedDrives.contains(targetDrive)) {
    error(
      "Unsupported Orin flash target drive '${targetDrive}' for '${orinTarget}'; " +
        "supported values: ${supportedDrives.join(', ')}"
    )
  }
  println "Downloaded Orin flash set to workspace: ${flashSet.flash_images_dir}"
  println "Downloaded ESP signature to workspace: ${flashSet.esp_signature_path}"
  println "Downloaded root signature to workspace: ${flashSet.root_signature_path}"
  sh "verify-signature image '${flashSet.esp_path}' '${flashSet.esp_signature_path}'"
  sh "verify-signature image '${flashSet.root_path}' '${flashSet.root_signature_path}'"

  def flasherPackageAttr = orin_flash_script_attr(orinTarget)
  println "Orin flash input: ${flashSet.flash_images_dir}"
  println "Orin flasher entrypoint: ${flashSet.flasher_entrypoint}"
  println "Orin flasher package attr: ${flasherPackageAttr}"

  return [
    flash_target_drive: targetDrive,
    flash_input_path: flashSet.flash_images_dir,
    flasher_entrypoint: flashSet.flasher_entrypoint,
    flasher_package_attr: flasherPackageAttr,
  ]
}

def run_orin_artifact_root_flash(
  String explicitFlakeRef,
  String imgUrl,
  String ociFlakeRef,
  String ociImageRef,
  String flasherPackageAttr,
  String flasherEntrypoint,
  String flashTargetDrive,
  String flashInputPath
) {
  def ghafFlakeRef = resolve_ghaf_flake_ref(explicitFlakeRef, imgUrl, ociFlakeRef)
  if (!ghafFlakeRef) {
    if (ociImageRef?.trim()) {
      error("Missing GHAF_FLAKE_REF and unable to derive it from OCI image '${ociImageRef}'")
    }
    error("Missing GHAF_FLAKE_REF and unable to derive Ghaf commit from IMG_URL '${imgUrl}'.")
  }

  println "Building Orin flash-script from GHAF_FLAKE_REF: ${ghafFlakeRef}"
  def flashScriptPath = artifactSupport.run_cmd(
    "nix build --no-link --print-out-paths '${ghafFlakeRef}#${flasherPackageAttr}'"
  )
  sh """
    /run/wrappers/bin/sudo '${flashScriptPath}/${flasherEntrypoint}' \
      --target='${flashTargetDrive}' \
      --flash-images='${flashInputPath}'
  """
  return ghafFlakeRef
}

def run_hw_test(
  String buildShortname,
  String testTargetName,
  String testIdentity,
  String testset,
  String testagent_host,
  Map oci_result,
  boolean secureboot,
  String ci_env,
  String deviceTag = null,
  String imgUrl = null,
  String ghafFlakeRef = null,
  String flashTargetDrive = null) {
  // Keep the blocking downstream wait outside node('built-in') so ghaf-hw-test
  // can acquire a controller executor for its own initialization stages.
  def build_href = "<a href=\"${pipelineModel.html_escape(env.BUILD_URL)}\">" +
    "${pipelineModel.html_escape("${env.JOB_NAME}#${env.BUILD_ID}")}</a>"
  def normalizedTestTarget = testTargetName?.trim()
  def normalizedTestIdentity = testIdentity?.trim()
  def normalizedDeviceTag = deviceTag?.trim()
  def desc = normalizedTestIdentity ?
    "Triggered by ${build_href}<br>(${pipelineModel.html_escape(normalizedTestIdentity)})" :
    "Triggered by ${build_href}<br>(${pipelineModel.html_escape(buildShortname)})"
  def test_params = [
    string(name: "TESTSET", value: testset),
    string(name: "DESC", value: desc),
    string(name: "TESTAGENT_HOST", value: testagent_host ?: ''),
    booleanParam(name: "USE_FLAKE_PINNED_CI_TEST", value: ci_env == "release"),
    booleanParam(name: "RELOAD_ONLY", value: false),
    booleanParam(name: "SECUREBOOT", value: secureboot),
  ]
  if (oci_result != null) {
    test_params << string(name: "OCI_IMAGE_REF", value: oci_result.primary.reference)
  } else if (imgUrl?.trim()) {
    test_params << string(name: "IMG_URL", value: imgUrl.trim())
    if (ghafFlakeRef?.trim()) {
      test_params << string(name: "GHAF_FLAKE_REF", value: ghafFlakeRef.trim())
    }
    if (flashTargetDrive?.trim()) {
      test_params << string(name: "FLASH_TARGET_DRIVE", value: flashTargetDrive.trim())
    }
  } else {
    error("Missing OCI publish result or IMG_URL for ${buildShortname}; cannot trigger ghaf-hw-test")
  }
  if (normalizedTestTarget) {
    test_params << string(name: "TEST_TARGET", value: normalizedTestTarget)
  }
  if (normalizedDeviceTag) {
    test_params << string(name: "DEVICE_TAG", value: normalizedDeviceTag)
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
    artifactSupport.append_to_build_description(
      "<a href=\"${pipelineModel.html_escape(job.url)}\">⛔ ${pipelineModel.html_escape(testIdentity)}</a>"
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
