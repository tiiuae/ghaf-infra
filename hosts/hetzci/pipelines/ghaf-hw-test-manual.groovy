#!/usr/bin/env groovy

// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////

def TMP_IMG_DIR = './image'
def CONF_FILE_PATH = '/etc/jenkins/test_config.json'
env.BOOT_PASSED = 'true'

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
        Can be left empty, in which case DEVICE_TAG must be specified. With installer image this is mantadory to give!'''.stripIndent()),
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
          script: "return ['orin-agx','orin-agx-64','orin-nx','lenovo-x1','dell-7330','darter-pro', 'x1-sec-boot']"
        ]
      ]
    ],
    [
      $class: 'ChoiceParameter',
      name: 'TESTAGENT_HOST',
      choiceType: 'PT_RADIO',
      description: '''
        Select the testagent-host. This parameter allows specifying the exact testagent in case Jenkins controller is
        connected with multiple agents. Can be used together with both IMG_URL and DEVICE_TAG parameters.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['dev','prod','release']"
        ]
      ]
    ],
    booleanParam(name: 'BOOT', defaultValue: true, description: 'Run boot test before any other tests (if any).'),
    booleanParam(name: 'WIPE_ONLY', defaultValue: false, description: 'Run just internal memory wiping stage! Use this option ONLY with installer image!.'),
    booleanParam(name: 'TURN_OFF', defaultValue: false, description: 'Turn off the device after other tests (if any).'),
  ])
])

////////////////////////////////////////////////////////////////////////////////

def init() {
  println(params)
  if(!params || params.RELOAD_ONLY) {
    return 'built-in'
  }
  def deviceMap = [
    "orin-agx"           : [name: 'OrinAGX1'],
    "orin-agx-64"        : [name: 'OrinAGX64'],
    "orin-nx"            : [name: 'OrinNX1'],
    "dell-7330"          : [name: 'Dell7330'],
    "darter-pro"         : [name: 'DarterPRO'],
    "lenovo-x1"          : [name: 'LenovoX1-1'],
    "x1-sec-boot"        : [name: 'X1-Secure-Boot']
  ]
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
  } else if(params.IMG_URL.contains("lenovo-x1-carbon-gen11-debug-signed")) {
    env.DEVICE_NAME = 'X1-Secure-Boot'
    env.DEVICE_TAG = 'x1-sec-boot'
  } else if(params.IMG_URL.contains("lenovo-x1-")) {
    env.DEVICE_NAME = 'LenovoX1-1'
    env.DEVICE_TAG = 'lenovo-x1'
  } else if(params.IMG_URL.contains("dell-latitude-7330-")) {
    env.DEVICE_NAME = 'Dell7330'
    env.DEVICE_TAG = 'dell-7330'
  } else if(params.IMG_URL.contains("system76-darp11-b-")) {
    env.DEVICE_NAME = 'DarterPRO'
    env.DEVICE_TAG = 'darter-pro'
  }
  if (!env.DEVICE_TAG || env.DEVICE_TAG == null) {
    error("DEVICE_TAG is not defined and could not be derived from IMG_URL ${env.IMG_URL}")
  }
  if (!params.IMG_URL || params.IMG_URL == null) {
    env.DEVICE_NAME = deviceMap[env.DEVICE_TAG].name
  }
  def label = env.DEVICE_TAG
  if (params.TESTAGENT_HOST) {
    label = "${params.TESTAGENT_HOST}-${env.DEVICE_TAG}"
  }
  println("Using DEVICE_NAME: ${env.DEVICE_NAME}")
  println("Using DEVICE_TAG: ${env.DEVICE_TAG}")
  currentBuild.description = "${label}"

  if (env.DEVICE_TAG == "x1-sec-boot") {
    env.DEVICE_BOOT_TAG = "lenovo-x1"
  } else {
    env.DEVICE_BOOT_TAG = env.DEVICE_TAG
  }
  def testagent_nodes = nodesByLabel(label: label, offline: false)
  if (!testagent_nodes) {
    error("No test agents online")
  }
  return label
}

def sh_ret_out(String cmd) {
  // Run cmd returning stdout
  return sh(script: cmd, returnStdout:true).trim()
}

def run_wget(String url, String to_dir) {
  // Download `url` setting the directory prefix `to_dir` preserving
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
    sh 'rm -f *.txt *.png *.mp4 *.wav output.xml report.html log.html'
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
      if (tags.contains('boot')) {
        // Set an environment variable to indicate boot test failed
        env.BOOT_PASSED = 'false'
      }
    } finally {
      // Move the test output (if any) to a subdirectory
      sh """
        rm -fr $tags; mkdir -p $tags
        mv -f *.txt *.png *.mp4 *.wav output.xml report.html log.html $tags/ || true
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
          if(params.IMG_URL.contains("microchip-icicle-")) {
            def muxport = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usb_sd_mux_port')
            env.MOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} host; sleep 10"
            env.UNMOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} dut"
          } else {
            def serial = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usbhub_serial')
            env.MOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}; sleep 10"
            env.UNMOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}"
          }
          // Mount the target disk
          sh "${env.MOUNT_CMD}"
          // Read the device name
          def dev = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'ext_drive_by-id')
          println "Checking that flash target '$dev' is connected..."
          sh """
            if /run/wrappers/bin/sudo test -f ${dev}; then
              echo "dev ${dev} found as regular file, removing the file and trying re-mount"
              ${env.UNMOUNT_CMD}; /run/wrappers/bin/sudo rm ${dev}; ${env.MOUNT_CMD}
            fi
            if ! /run/wrappers/bin/sudo test -L ${dev}; then
              echo "Symlink ${dev} not found. Failed to connect target USB disk to test agent."
              echo "Check USB cables. Maybe need to reboot test agent or Acroname USB hub."
              echo "Aborting flashing ${env.DEVICE_NAME}"
              exit 1
            fi
          """
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
          sh "${env.UNMOUNT_CMD}"
          currentBuild.description = "${currentBuild.description}<br>✅ Device flashed"
        }
      }
    }
    stage('Run Ghaf-installer') {
      when { expression { env.IMG_URL.contains("lenovo-x1-carbon-gen11-debug-installer") && !params.WIPE_ONLY } }
      steps {
        script {
          println "Run ghaf-installer"
          ghaf_robot_test('installer')
          println "Disconnect SSD from the laptop"
          sh "${env.MOUNT_CMD}"
        }
      }
    }
    stage('Boot test') {
      when { expression { params && params.BOOT && !params.WIPE_ONLY } }
      steps {
        script {
          ghaf_robot_test("relaybootAND${env.DEVICE_BOOT_TAG}")
        }
      }
    }
    stage('HW test') {
      when { expression { env.BOOT_PASSED == 'true' && params.TEST_TAGS && !params.WIPE_ONLY } }
      steps {
        script {
          ghaf_robot_test("${params.TEST_TAGS}")
        }
      }
    }
    stage('Wipe system') {
      when { expression { env.IMG_URL.contains("lenovo-x1-carbon-gen11-debug-installer") } }
      steps {
        script {
          ghaf_robot_test('turnoff')
          println "Connect SSD to the laptop"
          sh "${env.UNMOUNT_CMD}; sleep 10"
          println "Wipe the internal memory of the laptop"
          ghaf_robot_test('wiping')
        }
      }
    }
    stage('Turn off') {
      when { expression { params && params.TURN_OFF } }
      steps {
        script {
          ghaf_robot_test("relay-turnoff")
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
            'Robot-Framework/test-suites/**/*.wav, ' +
            'Robot-Framework/test-suites/**/*.txt'
          archiveArtifacts allowEmptyArchive: true, artifacts: test_artifacts
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
