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
    string(name: 'TEST_TAGS', defaultValue: '', description: 'Target test tags, e.g.: appsORbusinessvm, SP-T140, SP-T45ORSP-T60, etc.'),
    string(
      name: 'IMG_URL',
      defaultValue: '',
      description: '''
        Target image url. If specified, the target device is flashed with the given image before running the tests.
        Can be left empty, in which case DEVICE_TAG must be specified.'''.stripIndent()),
    [
      $class: 'ChoiceParameter',
      name: 'DEVICE_TAG',
      choiceType: 'PT_RADIO',
      description: '''
        Select the target device. If DEVICE_TAG is selected and IMG_URL is left empty, the target device is not flashed.
        Instead, tests will be run against the image flashed on the target device at the time of triggering this job.
        If both IMG_URL and DEVICE_TAG are selected, IMG_URL takes precedence.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['orin-agx','orin-agx-64','orin-nx','lenovo-x1','dell-7330','darter-pro']"
        ]
      ]
    ],
    booleanParam(name: 'BOOT', defaultValue: true, description: 'Run boot test before any other tests (if any).'),
    booleanParam(name: 'TURN_OFF', defaultValue: false, description: 'Turn off the device after other tests (if any).'),
    booleanParam(name: 'USE_RELAY', defaultValue: true, description: 'Use relay board to cut power from the target device.')
  ])
])

////////////////////////////////////////////////////////////////////////////////

def init() {
  println(params)
  if(!params || params.RELOAD_ONLY) {
    return 'built-in'
  }
  def deviceMap = [
    "orin-agx"           : [name: 'OrinAGX1',   urlmatch: 'orin-agx-'],
    "orin-agx-64"        : [name: 'OrinAGX64',  urlmatch: 'orin-agx64-'],
    "orin-nx"            : [name: 'OrinNX1',    urlmatch: 'orin-nx-'],
    "lenovo-x1"          : [name: 'LenovoX1-1', urlmatch: 'lenovo-x1-'],
    "dell-7330"          : [name: 'Dell7330',   urlmatch: 'dell-latitude-7330-'],
    "darter-pro"         : [name: 'DarterPRO',  urlmatch: 'system76-darp11-b-']
  ]
  if (params.IMG_URL) {
    for (tag in deviceMap.keySet()) {
      if (params.IMG_URL.contains(deviceMap[tag].urlmatch)) {
        env.DEVICE_TAG = tag
        break
      }
    }
  }
  if (!env.DEVICE_TAG || env.DEVICE_TAG == null) {
    error("DEVICE_TAG is not defined and could not be derived from IMG_URL ${env.IMG_URL}")
  }
  env.DEVICE_NAME = deviceMap[env.DEVICE_TAG].name
  println("Using DEVICE_NAME: ${env.DEVICE_NAME}")
  println("Using DEVICE_TAG: ${env.DEVICE_TAG}")
  currentBuild.description = "${env.DEVICE_TAG}"
  env.BOOT_TAG = "boot"
  env.POWEROFF_TAG = "turnoff"
  if (params.USE_RELAY) {
    env.BOOT_TAG = "relayboot"
    env.POWEROFF_TAG = "relay-turnoff"
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

def ghaf_robot_test(String tags) {
  env.ROBOT_EXECUTED = 'true'
  env.INCLUDE_TEST_TAGS = "${tags}"
  dir("Robot-Framework/test-suites") {
    sh 'rm -f *.txt *.png *.mp4 output.xml report.html log.html'
    try {
      // Pass variables as environment variables to shell.
      // Ref: https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#string-interpolation
      sh '''
        nix run .#ghaf-robot -- \
          -v DEVICE:$DEVICE_NAME \
          -v DEVICE_TYPE:$DEVICE_TAG \
          -v BUILD_ID:${BUILD_NUMBER} \
          -v COMMIT_HASH:NONE \
          -i $INCLUDE_TEST_TAGS .
      '''
      currentBuild.description = "${currentBuild.description}<br>✅ ${tags}"
    } catch (Exception e) {
      currentBuild.result = "FAILURE"
      unstable("FAILED '${tags}': ${e.toString()}")
      currentBuild.description = "${currentBuild.description}<br>⛔ ${tags}"
    } finally {
      // Move the test output (if any) to a subdirectory
      sh """
        rm -fr $tags; mkdir -p $tags
        mv -f *.txt *.png *.mp4 output.xml report.html log.html $tags/ || true
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
            echo { \\\"Job\\\": \\\"${env.DEVICE_TAG}\\\" } > ${TEST_CONFIG_DIR}/${BUILD_NUMBER}.json
            ls -la ${TEST_CONFIG_DIR}
          """
        }
      }
    }
    stage('Image download') {
      when { expression { params && params.IMG_URL } }
      steps {
        script {
          def img_path = run_wget(params.IMG_URL, TMP_IMG_DIR)
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
      when { expression { params && params.IMG_URL } }
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
            def SECTORS = sh(script: "/run/wrappers/bin/sudo blockdev --getsz ${dev}", returnStdout: true).trim()
            // Unmount possible mounted filesystems
            sh "sync; /run/wrappers/bin/sudo umount -q ${dev}* || true"
            // Wipe first 10MiB of disk
            sh "/run/wrappers/bin/sudo dd if=/dev/zero of=${dev} bs=${SECTOR} count=${MIB_TO_SECTORS} conv=fsync status=none"
            // Wipe last 10MiB of disk
            sh "/run/wrappers/bin/sudo dd if=/dev/zero of=${dev} bs=${SECTOR} count=${MIB_TO_SECTORS} seek=\$(( ${SECTORS} - ${MIB_TO_SECTORS} )) conv=fsync status=none"
          }
          // Write the image
          sh "/run/wrappers/bin/sudo dd if=${env.IMG_PATH} of=${dev} bs=1M status=progress conv=fsync"
          // Unmount
          sh "${unmount_cmd}"
          currentBuild.description = "${currentBuild.description}<br>✅ Device flashed"
        }
      }
    }
    stage('Boot test') {
      when { expression { params && params.BOOT } }
      steps {
        script {
          ghaf_robot_test("${env.BOOT_TAG}AND${env.DEVICE_TAG}")
        }
      }
    }
    stage('HW test') {
      when { expression { params.TEST_TAGS } }
      steps {
        script {
          ghaf_robot_test("${params.TEST_TAGS}")
        }
      }
    }
    stage('Turn off') {
      when { expression { params && params.TURN_OFF } }
      steps {
        script {
          ghaf_robot_test("${env.POWEROFF_TAG}")
        }
      }
    }
  }
  post {
    always {
      script {
        if (env.ROBOT_EXECUTED != null) {
          def test_artifacts = '' +
            'Robot-Framework/test-suites/**/*.html, ' +
            'Robot-Framework/test-suites/**/*.xml, ' +
            'Robot-Framework/test-suites/**/*.png, ' +
            'Robot-Framework/test-suites/**/*.mp4, ' +
            'Robot-Framework/test-suites/**/*.txt'
          archiveArtifacts allowEmptyArchive: true, artifacts: test_artifacts
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
