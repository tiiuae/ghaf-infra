#!/usr/bin/env groovy

@Library('ghafInfra') _

import groovy.transform.Field

// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////

@Field def TMP_IMG_DIR = './image'
@Field def CONF_FILE_PATH = '/etc/jenkins/test_config.json'
@Field def CI_TEST_PINNED_SOURCE_FILE = '/etc/jenkins/ci-test-automation-pinned-source'
@Field def IMAGE_MEDIA_TYPE = 'application/octet-stream'
@Field def SOURCE_REF_ANNOTATION = 'org.ghaf.source.ref'
@Field def TARGET_ANNOTATION = 'org.ghaf.target'
env.BOOT_PASSED = 'true'

////////////////////////////////////////////////////////////////////////////////

def pipelineParameters(boolean useFlakePinnedDefault = false) {
  return [
    booleanParam(
      name: 'USE_FLAKE_PINNED_CI_TEST',
      defaultValue: useFlakePinnedDefault,
      description: 'Use ci-test-automation source pinned in ghaf-infra flake. Defaults to enabled in release environment.'
    ),
    string(name: 'CI_TEST_REPO_URL', defaultValue: 'https://github.com/tiiuae/ci-test-automation.git', description: 'Select ci-test-automation repository.'),
    string(name: 'CI_TEST_REPO_BRANCH', defaultValue: 'main', description: 'Select ci-test-automation branch to checkout.'),
    string(name: 'TEST_TAGS', defaultValue: '', description: 'Target test tags, e.g.: lenovo-x1ANDapps, SP-T140, SP-T45ORSP-T60, etc.'),
    string(
      name: 'OCI_IMAGE_REF',
      defaultValue: '',
      description: '''
        Published OCI image reference. If specified, the target device is flashed with the published image before running the tests.
        Can be left empty, in which case IMG_URL or DEVICE_TAG may be used instead.'''.stripIndent()),
    string(
      name: 'IMG_URL',
      defaultValue: '',
      description: '''
        Target image url. If specified, the target device is flashed with the given image before running the tests.
        Can be left empty, in which case DEVICE_TAG must be specified. With installer image this is mandatory to give!'''.stripIndent()),
    string(
      name: 'GHAF_FLAKE_REF',
      defaultValue: '',
      description: '''
        Optional pinned Ghaf flake reference for flash-script. Leave empty to derive it from OCI metadata or IMG_URL.
        Set this explicitly for images built from refs that are not fetchable by commit SHA alone, such as PR merge refs.'''.stripIndent()),
    booleanParam(
      name: 'USE_LEGACY_DD_FLASH',
      defaultValue: false,
      description: 'Override flash-script usage and use the old-style dd flashing path instead. Intended for manual UI runs.'),
    [
      $class: 'ChoiceParameter',
      name: 'DEVICE_TAG',
      choiceType: 'PT_RADIO',
      description: '''
        Select the target device. If DEVICE_TAG is selected and both IMG_URL and OCI_IMAGE_REF are left empty, the target device is not flashed.
        Instead, tests will be run against the image flashed on the target device at the time of triggering this job.
        If IMG_URL or OCI_IMAGE_REF is selected together with DEVICE_TAG, the selected device is flashed with the given image.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['orin-agx','orin-agx-64','orin-nx','lenovo-x1','dell-7330','darter-pro', 'x1-sec-boot']"
        ]
      ]
    ],
    string(
      name: 'JOB_SELECTOR',
      defaultValue: '',
      description: '''
        Select the job. If device is flashed, the job is derived from OCI_IMAGE_REF or IMG_URL when available.
        Otherwise this selection is used.
        For example system76-darp11-b-storeDisk-debug-installer or system76-darp11-b-storeDisk-debug.
        DEVICE_TAG is used as the job by default when not flashing.'''.stripIndent()),
    [
      $class: 'ChoiceParameter',
      name: 'TESTAGENT_HOST',
      choiceType: 'PT_RADIO',
      description: '''
        Select the testagent-host. This parameter allows specifying the exact testagent in case Jenkins controller is
        connected with multiple agents. Can be used together with IMG_URL, OCI_IMAGE_REF, and DEVICE_TAG.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['dev','prod','release']"
        ]
      ]
    ],
    booleanParam(name: 'SECUREBOOT', defaultValue: false, description: 'Test on secure boot enabled hardware'),
    booleanParam(name: 'BOOT', defaultValue: true, description: 'Run boot test before any other tests (if any).'),
    booleanParam(name: 'WIPE_ONLY', defaultValue: false, description: 'Run just internal memory wiping stage! Use this option ONLY with installer image!.'),
    booleanParam(name: 'TURN_OFF', defaultValue: false, description: 'Turn off the device after other tests (if any).'),
  ]
}

properties([
  parameters(pipelineParameters(false))
])

////////////////////////////////////////////////////////////////////////////////

def init() {
  if(!params || params.RELOAD_ONLY) {
    return 'built-in'
  }
  env.OCI_TARGET = ''
  env.OCI_SOURCE_REF = ''
  if (params.OCI_IMAGE_REF) {
    def annotations = readJSON(
      text: utils.run_cmd("oras manifest fetch --format json '${params.OCI_IMAGE_REF}'")
    ).content?.annotations ?: [:]
    env.OCI_TARGET = annotations[TARGET_ANNOTATION] ?: ''
    env.OCI_SOURCE_REF = annotations[SOURCE_REF_ANNOTATION] ?: ''
  }
  def flashTarget = utils.derive_target_name(params.IMG_URL, env.OCI_TARGET)
  def deviceInfo = null
  if (flashTarget) {
    deviceInfo = utils.derive_device_info(flashTarget, params.SECUREBOOT)
    if (!deviceInfo) {
      error("Unable to parse device config for target '${flashTarget}'")
    }
  }
  if (params.DEVICE_TAG) {
    def deviceName = utils.device_name_from_tag(params.DEVICE_TAG)
    if (!deviceName) {
      error("Unknown DEVICE_TAG '${params.DEVICE_TAG}'")
    }
    deviceInfo = [name: deviceName, tag: params.DEVICE_TAG]
  }
  if (!deviceInfo) {
    error("DEVICE_TAG is not defined and could not be derived from IMG_URL '${params.IMG_URL}', OCI_IMAGE_REF '${params.OCI_IMAGE_REF}', or explicit DEVICE_TAG")
  }
  env.DEVICE_NAME = deviceInfo.name
  env.DEVICE_TAG = deviceInfo.tag
  def label = params.TESTAGENT_HOST ? "${params.TESTAGENT_HOST}-${env.DEVICE_TAG}" : env.DEVICE_TAG
  def testagent_nodes = nodesByLabel(label: label, offline: false)
  if (!testagent_nodes) {
    error("No test agents online")
  }
  return label
}

def ghaf_robot_test(String tags) {
  env.ROBOT_EXECUTED = 'true'
  env.INCLUDE_TEST_TAGS = "${tags}"
  dir("Robot-Framework/test-suites") {
    sh 'rm -f *.txt *.png *.jpeg *.mp4 *.mkv *.wav output.xml report.html log.html'
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
        mv -f *.txt *.png *.jpeg *.mp4 *.mkv *.wav output.xml report.html log.html $tags/ || true
      """
    }
  }
}

////////////////////////////////////////////////////////////////////////////////

pipeline {
  agent none
  options {
    buildDiscarder(logRotator(numToKeepStr: '100'))
  }
  stages {
    stage('Set properties') {
      agent { label 'built-in' }
      steps {
        script {
          properties([
            parameters(pipelineParameters(env.CI_ENV == 'release'))
          ])
        }
      }
    }
    stage('Reload only') {
      agent { label 'built-in' }
      when { expression { params && params.RELOAD_ONLY } }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          currentBuild.displayName = "Reload pipeline"
          error('Reloading pipeline - aborting other stages')
        }
      }
    }
    stage('Initialize') {
      agent { label 'built-in' }
      steps {
        script {
          env.TEST_AGENT_LABEL = init()
        }
      }
    }
    stage('Run on test agent') {
      agent { label "${env.TEST_AGENT_LABEL}" }
      stages {
        stage('Resolve target') {
          steps {
            script {
              def explicitTarget = utils.derive_target_name(params.IMG_URL, env.OCI_TARGET)
              def jobSelector = params.JOB_SELECTOR?.trim()
              if (explicitTarget) {
                env.TARGET = explicitTarget
              } else if (jobSelector) {
                env.TARGET = jobSelector
              } else {
                env.TARGET = env.DEVICE_TAG
              }
              env.DEVICE_BOOT_TAG = utils.boot_tag_for(env.DEVICE_TAG)
              currentBuild.description = "${env.TEST_AGENT_LABEL}"
              println("Using TARGET: ${env.TARGET}")
              println("Using DEVICE_NAME: ${env.DEVICE_NAME}")
              println("Using DEVICE_TAG: ${env.DEVICE_TAG}")
            }
          }
        }
        stage('Checkout') {
          steps {
            deleteDir()
            script {
              utils.checkout_ci_test_sources(
                CI_TEST_PINNED_SOURCE_FILE,
                params.USE_FLAKE_PINNED_CI_TEST,
                params.CI_TEST_REPO_BRANCH,
                params.CI_TEST_REPO_URL
              )
            }
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
              // Determine mount commands
              if(env.TARGET.contains("microchip-icicle-")) {
                def muxport = utils.get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usb_sd_mux_port')
                env.MOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} host; sleep 10"
                env.UNMOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} dut"
              } else {
                def serial = utils.get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usbhub_serial')
                env.MOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}; sleep 10"
                env.UNMOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}; sleep 10"
              }
            }
          }
        }
        stage('Image download') {
          when { expression { params && (params.IMG_URL || params.OCI_IMAGE_REF) } }
          steps {
            script {
              def img_path
              if (params.OCI_IMAGE_REF) {
                def pullResult = readJSON(
                  text: utils.run_cmd("oras pull --format json -o '${TMP_IMG_DIR}' '${params.OCI_IMAGE_REF}'")
                )
                img_path = pullResult.files?.find { it.mediaType == IMAGE_MEDIA_TYPE }?.path
                if (!img_path) {
                  error("Unable to derive image file from OCI image '${params.OCI_IMAGE_REF}'")
                }
              } else {
                img_path = utils.run_wget(params.IMG_URL, TMP_IMG_DIR)
              }
              println "Downloaded image to workspace: ${img_path}"
              if (params.USE_LEGACY_DD_FLASH) {
                // Uncompress for the legacy dd flashing path.
                if(img_path.endsWith(".zst")) {
                  sh "zstd -dfv ${img_path}"
                  // env.IMG_PATH stores the path to the uncompressed image
                  env.IMG_PATH = img_path.substring(0, img_path.lastIndexOf('.'))
                } else {
                  env.IMG_PATH = img_path
                }
                println "Uncompressed image at: ${env.IMG_PATH}"
              } else {
                // flash-script handles .zst natively; pass the original download path.
                env.FLASH_INPUT_PATH = img_path
                println "Flash input: ${env.FLASH_INPUT_PATH}"
              }
            }
          }
        }
        stage('Flash') {
          when { expression { params && (params.IMG_URL || params.OCI_IMAGE_REF) } }
          steps {
            script {
              // Mount the target disk
              sh "${env.MOUNT_CMD}"
              // Read the device name
              def dev = utils.get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'ext_drive_by-id')
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
              if (params.USE_LEGACY_DD_FLASH) {
                // Wipe possible ZFS leftovers, more details here:
                // https://github.com/tiiuae/ghaf/blob/454b18bc/packages/installer/ghaf-installer.sh#L75
                if(env.TARGET.contains("lenovo-x1")) {
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
              } else {
                if (env.FLASH_INPUT_PATH.endsWith('.raw')) {
                  error("flash-script does not support '.raw' images. Enable USE_LEGACY_DD_FLASH to flash '${env.FLASH_INPUT_PATH}' with dd.")
                }
                def ghafFlakeRef = utils.resolve_ghaf_flake_ref(params.GHAF_FLAKE_REF, params.IMG_URL, env.OCI_SOURCE_REF)
                if (!ghafFlakeRef) {
                  if (params.OCI_IMAGE_REF) {
                    error("Missing GHAF_FLAKE_REF and unable to derive it from OCI image '${params.OCI_IMAGE_REF}'. Set GHAF_FLAKE_REF or enable USE_LEGACY_DD_FLASH.")
                  }
                  error("Missing GHAF_FLAKE_REF and unable to derive Ghaf commit from IMG_URL '${params.IMG_URL}'. Set GHAF_FLAKE_REF or enable USE_LEGACY_DD_FLASH.")
                }
                println "Building flash-script from GHAF_FLAKE_REF: ${ghafFlakeRef}"
                def flashScriptPath = utils.run_cmd(
                  "nix build --no-link --print-out-paths '${ghafFlakeRef}#packages.x86_64-linux.flash-script'"
                )
                // flash-script validates /dev/sdX format; resolve the by-id symlink.
                def resolved_dev = utils.run_cmd("/run/wrappers/bin/sudo readlink -f ${dev}")
                sh "/run/wrappers/bin/sudo ${flashScriptPath}/bin/flash-script -d ${resolved_dev} -i ${env.FLASH_INPUT_PATH} -f"
              }
              // Unmount
              sh "${env.UNMOUNT_CMD}"
              sh """
                if /run/wrappers/bin/sudo test -L ${dev}; then
                  echo "Symlink ${dev} was found. Failed to unmount target USB disk from test agent."
                  exit 1
                fi
              """
              currentBuild.description = "${currentBuild.description}<br>✅ Device flashed"
            }
          }
        }
        stage('Run Ghaf-installer') {
          when { expression { env.TARGET.contains("installer") && !params.WIPE_ONLY } }
          steps {
            script {
              sh "${env.UNMOUNT_CMD}"
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
          when { expression { env.TARGET.contains("installer")} }
          steps {
            script {
              if (env.TARGET.contains("installer") && env.DEVICE_TAG == "darter-pro") {
                ghaf_robot_test('break')
              }
              ghaf_robot_test('relay-turnoff')
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
            utils.archive_robot_artifacts(TMP_IMG_DIR, env.ROBOT_EXECUTED != null)
          }
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
