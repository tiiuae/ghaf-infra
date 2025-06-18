#!/usr/bin/env groovy

// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////

def TMP_IMG_DIR = './image'
def CONF_FILE_PATH = '/etc/jenkins/test_config.json'

////////////////////////////////////////////////////////////////////////////////

properties([
  parameters([
    string(name: 'CI_TEST_REPO_URL', defaultValue: 'https://github.com/tiiuae/ci-test-automation.git', description: 'Select ci-test-automation repository.'),
    string(name: 'CI_TEST_REPO_BRANCH', defaultValue: 'main', description: 'Select ci-test-automation branch to checkout.'),
    string(name: 'IMG_URL', defaultValue: '', description: 'Target image url.'),
    string(name: 'TESTSET', defaultValue: '_relayboot_', description: 'Target testset, e.g.: _relayboot_, _relayboot_bat_, _relayboot_pre-merge_, etc.)')
  ])
])

////////////////////////////////////////////////////////////////////////////////

def init() {
  if(!params || params.RELOAD_ONLY) {
    return 'built-in'
  }
  if(params.IMG_URL.isEmpty() ) {
    error("Missing IMG_URL parameter")
  }
  // Parse out the TARGET from the IMG_URL
  def match = params.IMG_URL =~ /commit_[0-9a-f]{5,40}\/([^\/]+)/
  if(match) {
    env.TARGET = "${match.group(1)}"
    match = null // https://stackoverflow.com/questions/40454558
    println("Using TARGET: ${env.TARGET}")
  } else {
    error("Unexpected IMG_URL: ${params.IMG_URL}")
  }
  // Determine the device name
  if(params.IMG_URL.contains("orin-agx-")) {
    env.DEVICE_NAME = 'OrinAGX1'
    env.DEVICE_TAG = 'orin-agx'
  } else if(params.IMG_URL.contains("orin-agx64-")) {
    env.DEVICE_NAME = 'OrinAGX64'
    env.DEVICE_TAG = 'orin-agx-64'
  } else if(params.IMG_URL.contains("orin-nx-")) {
    env.DEVICE_NAME = 'OrinNX1'
    env.DEVICE_TAG = 'orin-nx'
  } else if(params.IMG_URL.contains("lenovo-x1-")) {
    env.DEVICE_NAME = 'LenovoX1-1'
    env.DEVICE_TAG = 'lenovo-x1'
  } else if(params.IMG_URL.contains("generic-x86_64-")) {
    env.DEVICE_NAME = 'NUC1'
    env.DEVICE_TAG = 'nuc'
  } else if(params.IMG_URL.contains("microchip-icicle-")) {
    env.DEVICE_NAME = 'Polarfire1'
    env.DEVICE_TAG = 'riscv'
  } else if(params.IMG_URL.contains("dell-latitude-7330-")) {
    env.DEVICE_NAME = 'Dell7330'
    env.DEVICE_TAG = 'dell-7330'
  } else {
    error("Unable to parse device config for image '${params.IMG_URL}'")
  }
  println("Using DEVICE_NAME: ${env.DEVICE_NAME}")
  println("Using DEVICE_TAG: ${env.DEVICE_TAG}")
  if(params.containsKey('DESC')) {
    currentBuild.description = "${params.DESC}"
  } else {
    currentBuild.description = "${env.TARGET}"
  }
  def testagent_nodes = nodesByLabel(label: env.DEVICE_TAG, offline: false)
  if (!testagent_nodes) {
    error("No test agents online")
  }
  return env.DEVICE_TAG
}

def sh_ret_out(String cmd) {
  // Run cmd returning stdout
  return sh(script: cmd, returnStdout:true).trim()
}

def run_wget(String url, String to_dir) {
  // Downlaod `url` setting the directory prefix `to_dir` preserving
  // the hierarchy of directories locally.
  sh "wget --show-progress --progress=dot:giga --force-directories --timestamping -P ${to_dir} ${url}"
  // Re-run wget: this will not re-download anything, it's needed only to
  // get the local path to the downloaded file
  return sh_ret_out("wget --force-directories --timestamping -P ${to_dir} ${url} 2>&1 | grep -Po '${to_dir}[^’]+'")
}

def get_test_conf_property(String file_path, String device, String property) {
  // Get the requested device property data from test_config.json file
  def device_data = readJSON file: file_path
  def property_data = "${device_data['addresses'][device][property]}"
  println "Got device '${device}' property '${property}' value: '${property_data}'"
  return property_data
}

def ghaf_robot_test(String testname='relayboot') {
  if (!env.DEVICE_TAG) {
    error("DEVICE_TAG not set")
  }
  if (!env.DEVICE_NAME) {
    error("DEVICE_NAME not set")
  }
  if (testname.contains('turnoff')) {
    env.INCLUDE_TEST_TAGS = "${testname}"
  } else {
    env.INCLUDE_TEST_TAGS = "${testname}AND${env.DEVICE_TAG}"
  }
  dir("Robot-Framework/test-suites") {
    sh 'rm -f *.txt *.png output.xml report.html log.html'
    // On failure, continue the pipeline execution
    env.COMMIT_HASH = (params.IMG_URL =~ /commit_([a-f0-9]{40})/)[0][1]
    try {
      // Pass variables as environment variables to shell.
      // Ref: https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#string-interpolation
      sh '''
        nix run .#ghaf-robot -- \
          -v DEVICE:$DEVICE_NAME \
          -v DEVICE_TYPE:$DEVICE_TAG \
          -v BUILD_ID:${BUILD_NUMBER} \
          -v COMMIT_HASH:$COMMIT_HASH \
          -i $INCLUDE_TEST_TAGS .
      '''
      if (testname.contains('boot')) {
        // Set an environment variable to indicate boot test passed
        env.BOOT_PASSED = 'true'
      }
    } catch (Exception e) {
      currentBuild.result = "FAILURE"
      unstable("FAILED '${testname}': ${e.toString()}")
    } finally {
      // Move the test output (if any) to a subdirectory
      sh """
        rm -fr $testname; mkdir -p $testname
        mv -f *.txt *.png output.xml report.html log.html $testname/ || true
      """
    }
  }
}

////////////////////////////////////////////////////////////////////////////////

pipeline {
  agent { label init() }
  options {
    buildDiscarder(logRotator(numToKeepStr: '100'))
  }
  stages {
    stage('Reload only') {
      when { expression { params && params.RELOAD_ONLY } }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          currentBuild.displayName = "Reload pipeline"
          error('Reloading pipeline - aborting other stages')
        }
      }
    }
    stage('Checkout') {
      steps {
        checkout scmGit(
          branches: [[name: "${params.CI_TEST_REPO_BRANCH}"]],
          extensions: [[$class: 'WipeWorkspace']],
          userRemoteConfigs: [[url: CI_TEST_REPO_URL]]
        )
      }
    }
    stage('Setup') {
      steps {
        script {
          env.TEST_CONFIG_DIR = 'Robot-Framework/config'
          sh """
            mkdir -p ${TEST_CONFIG_DIR}
            rm -f ${TEST_CONFIG_DIR}/*.json
            ln -sv ${CONF_FILE_PATH} ${TEST_CONFIG_DIR}
            echo { \\\"Job\\\": \\\"${env.TARGET}\\\" } > ${TEST_CONFIG_DIR}/${BUILD_NUMBER}.json
            ls -la ${TEST_CONFIG_DIR}
          """
        }
      }
    }
    stage('Image download') {
      steps {
        script {
          img_path = run_wget(params.IMG_URL, TMP_IMG_DIR)
          println "Downloaded image to workspace: ${img_path}"
          // Uncompress
          if(img_path.endsWith(".zst")) {
            sh "zstd -dfv ${img_path}"
            // env.IMG_PATH stores the path to the uncompressed image
            env.IMG_PATH = img_path.substring(0, img_path.lastIndexOf('.'))
          } else {
            env.IMG_PATH = img_path
          }
          println "Uncompressed image at: ${env.IMG_PATH}"
        }
      }
    }
    stage('Flash') {
      steps {
        // TODO: We should use ghaf flashing scripts or installers.
        // We don't want to maintain these flashing details here:
        script {
          // Determine mount commands
          def mount_cmd, unmount_cmd
          if(params.IMG_URL.contains("microchip-icicle-")) {
            def muxport = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usb_sd_mux_port')
            mount_cmd = "/run/wrappers/bin/sudo usbsdmux ${muxport} host; sleep 10"
            unmount_cmd = "/run/wrappers/bin/sudo usbsdmux ${muxport} dut"
          } else {
            def serial = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usbhub_serial')
            mount_cmd = "/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}; sleep 10"
            unmount_cmd = "/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}"
          }
          // Mount the target disk
          sh "${mount_cmd}"
          // Read the device name
          def dev = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'ext_drive_by-id')
          println "Using device '$dev'"
          // Wipe possible ZFS leftovers, more details here:
          // https://github.com/tiiuae/ghaf/blob/454b18bc/packages/installer/ghaf-installer.sh#L75
          if(params.IMG_URL.contains("lenovo-x1-")) {
            echo "Wiping filesystem..."
            def SECTOR = 512
            def MIB_TO_SECTORS = 20480
            // Disk size in 512-byte sectors
            def SECTORS = sh(script: "/run/wrappers/bin/sudo blockdev --getsz /dev/disk/by-id/${dev}", returnStdout: true).trim()
            // Unmount possible mounted filesystems
            sh "sync; /run/wrappers/bin/sudo umount -q /dev/disk/by-id/${dev}* || true"
            // Wipe first 10MiB of disk
            sh "/run/wrappers/bin/sudo dd if=/dev/zero of=/dev/disk/by-id/${dev} bs=${SECTOR} count=${MIB_TO_SECTORS} conv=fsync status=none"
            // Wipe last 10MiB of disk
            sh "/run/wrappers/bin/sudo dd if=/dev/zero of=/dev/disk/by-id/${dev} bs=${SECTOR} count=${MIB_TO_SECTORS} seek=\$(( ${SECTORS} - ${MIB_TO_SECTORS} )) conv=fsync status=none"
          }
          // Write the image
          sh "/run/wrappers/bin/sudo dd if=${env.IMG_PATH} of=/dev/disk/by-id/${dev} bs=1M status=progress conv=fsync"
          // Unmount
          sh "${unmount_cmd}"
        }
      }
    }
    stage('Relay Boot test') {
      when { expression { env.TESTSET.contains('_relayboot_')} }
      steps {
        script {
          env.BOOT_PASSED = 'false'
          ghaf_robot_test('relayboot')
          println "Relay boot test passed: ${env.BOOT_PASSED}"
        }
      }
    }
    stage('Pre-merge test') {
      when { expression { env.BOOT_PASSED == 'true' && env.TESTSET.contains('_pre-merge_')} }
      steps {
        script {
          ghaf_robot_test('pre-merge')
        }
      }
    }
    stage('Bat test') {
      when { expression { env.BOOT_PASSED == 'true' && env.TESTSET.contains('_bat_')} }
      steps {
        script {
          ghaf_robot_test('bat')
        }
      }
    }
    stage('GUI test') {
      when { expression { env.BOOT_PASSED == 'true' && env.TESTSET.contains('_gui_')} }
      steps {
        script {
          ghaf_robot_test('gui')
        }
      }
    }
    stage('Perf test') {
      when { expression { env.BOOT_PASSED == 'true' && env.TESTSET.contains('_perf_')} }
      steps {
        script {
          ghaf_robot_test('performance')
        }
      }
    }
    stage('Relay Turn off') {
      steps {
        script {
          ghaf_robot_test('relay-turnoff')
        }
      }
    }
  }
  post {
    always {
      script {
        if (env.BOOT_PASSED != null) {
          def test_artifacts = '' +
            'Robot-Framework/test-suites/**/*.html, ' +
            'Robot-Framework/test-suites/**/*.xml, ' +
            'Robot-Framework/test-suites/**/*.png, ' +
            'Robot-Framework/test-suites/**/*.txt'
          archiveArtifacts allowEmptyArchive: true, artifacts: test_artifacts
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
