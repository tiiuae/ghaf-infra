#!/usr/bin/env groovy

@Library('ghafInfra') _

import groovy.transform.Field

// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////

@Field def TMP_IMG_DIR = './image'
@Field def CONF_FILE_PATH = '/etc/jenkins/test_config.json'
@Field def CI_TEST_PINNED_SOURCE_FILE = '/etc/jenkins/ci-test-automation-pinned-source'
@Field def IN_TOTO_MEDIA_TYPE = 'application/vnd.in-toto+json'
@Field def DETACHED_SIGNATURE_MEDIA_TYPE = 'application/vnd.ghaf.signature.v1'
@Field def IMAGE_MEDIA_TYPE = 'application/octet-stream'
@Field def SOURCE_REF_ANNOTATION = 'org.ghaf.source.ref'
@Field def TARGET_ANNOTATION = 'org.ghaf.target'
@Field def SOURCE_REVISION_ANNOTATION = 'org.opencontainers.image.revision'

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
    string(name: 'OCI_IMAGE_REF', defaultValue: '', description: 'Published OCI image reference.'),
    string(name: 'IMG_URL', defaultValue: '', description: 'Target image url.'),
    string(name: 'GHAF_FLAKE_REF', defaultValue: '', description: 'Pinned Ghaf flake reference for flash-script. If empty, derive it from OCI metadata or IMG_URL commit.'),
    string(name: 'TESTSET', defaultValue: '_relayboot_', description: 'Target testset, e.g.: _relayboot_, _relayboot_bat_, _relayboot_pre-merge_, etc.'),
    string(name: 'TESTAGENT_HOST', defaultValue: null, description: 'Target testagent host, e.g.: dev, prod, release'),
    booleanParam(name: 'SECUREBOOT', defaultValue: false, description: 'Test on secure boot enabled hardware'),
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
  def ociImageRef = params.OCI_IMAGE_REF?.trim()
  def imgUrl = params.IMG_URL?.trim()
  env.OCI_TARGET = ''
  env.OCI_SOURCE_REF = ''
  env.OCI_IMAGE_REVISION = ''
  if (ociImageRef) {
    def annotations = readJSON(
      text: sh_ret_out("oras manifest fetch --format json '${ociImageRef}'")
    ).content?.annotations ?: [:]
    env.OCI_TARGET = annotations[TARGET_ANNOTATION] ?: ''
    env.OCI_SOURCE_REF = annotations[SOURCE_REF_ANNOTATION] ?: ''
    env.OCI_IMAGE_REVISION = annotations[SOURCE_REVISION_ANNOTATION] ?: ''
  }
  if (!ociImageRef && !imgUrl) {
    error("Missing OCI_IMAGE_REF or IMG_URL parameter")
  }
  env.TARGET = utils.derive_target_name(imgUrl, env.OCI_TARGET)
  if (!env.TARGET) {
    if (ociImageRef) {
      error("Unable to derive target name from OCI image '${ociImageRef}'")
    }
    error("Unexpected IMG_URL: ${params.IMG_URL}")
  }
  println("Using TARGET: ${env.TARGET}")

  def deviceInfo = utils.derive_device_info(env.TARGET, params.SECUREBOOT)
  if (!deviceInfo) {
    error("Unable to parse device config for target '${env.TARGET}'")
  }
  env.DEVICE_NAME = deviceInfo.name
  env.DEVICE_TAG = deviceInfo.tag
  println("Using DEVICE_NAME: ${env.DEVICE_NAME}")
  println("Using DEVICE_TAG: ${env.DEVICE_TAG}")
  // Determine additional test tags based on target
  def tagFilters = []
  if (env.TARGET.contains("lenovo-x1") || env.TARGET.contains("darp11-b")) {
    if (env.TARGET.contains("storeDisk")) {
      tagFilters.add('NOTexcl-storeDisk')
    } else {
      tagFilters.add('NOTstoreDisk-only')
    }
    if (env.TARGET.contains("installer")) {
      tagFilters.add('NOTexcl-installer')
    } else {
      tagFilters.add('NOTinstaller-only')
    }
  }
  if (env.TARGET.contains("lenovo-x1")) {
    if (env.DEVICE_TAG == 'x1-sec-boot') {
      tagFilters.add('NOTexcl-secboot')
    } else {
      tagFilters.add('NOTsecboot-only')
    }
  }
  env.EXTRATAG = tagFilters.unique().join('')
  if (env.EXTRATAG) {
    println("Using additional test tags: ${tagFilters}")
  } else {
    println("No additional test tags are used")
  }
  if(params.containsKey('DESC')) {
    currentBuild.description = "${params.DESC}"
  } else {
    currentBuild.description = "${env.TARGET}"
  }
  def testagent_nodes = nodesByLabel(label: env.DEVICE_TAG, offline: false)
  if (!testagent_nodes) {
    error("No test agents online")
  }
  def label = env.DEVICE_TAG
  if (params.TESTAGENT_HOST) {
    println("Using specific TESTAGENT_HOST: ${TESTAGENT_HOST}")
    label = "${params.TESTAGENT_HOST}-${env.DEVICE_TAG}"
  }
  return label
}

def sh_ret_out(String cmd) {
  // Run cmd returning stdout
  return sh(script: cmd, returnStdout:true).trim()
}

def oras_pull_json(String reference, String outputDir) {
  return readJSON(
    text: sh_ret_out("oras pull --format json -o '${outputDir}' '${reference}'")
  )
}

def run_wget(String url, String to_dir) {
  // Download `url` setting the directory prefix `to_dir` preserving
  // the hierarchy of directories locally.
  sh "wget --show-progress --progress=dot:giga --force-directories --timestamping -P ${to_dir} ${url}"
  // Re-run wget: this will not re-download anything, it's needed only to
  // get the local path to the downloaded file
  return sh_ret_out("wget --force-directories --timestamping -P ${to_dir} ${url} 2>&1 | grep -Po '${to_dir}[^’]+'")
}

@NonCPS
def find_oci_pull_file(Map pullResult, String mediaType) {
  def file = pullResult.files?.find { it.mediaType == mediaType }
  return file?.path
}

@NonCPS
def split_img_url(String img_url) {
  // Why NonCPS? See: https://stackoverflow.com/a/48465528
  def match = img_url =~ /(.*commit_[a-f0-9]{40})\/([^\/]+)\/(.+)/
  def split = [
    "artifacts_url"   : match[0][1],
    "target_name"     : match[0][2],
    "img_relpath"     : match[0][3]
  ]
  return split
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
  if (env.DEVICE_TAG == "x1-sec-boot") {
    env.DEVICE_TEST_TAG = "lenovo-x1"
  } else {
    env.DEVICE_TEST_TAG = env.DEVICE_TAG
  }
  if (testname.contains('turnoff')) {
    env.INCLUDE_TEST_TAGS = "${testname}"
  } else {
    env.INCLUDE_TEST_TAGS = "${env.DEVICE_TEST_TAG}AND${testname}${env.EXTRATAG}"
  }
  dir("Robot-Framework/test-suites") {
    sh 'rm -f *.txt *.png *.jpeg *.mp4 *.mkv *.wav output.xml report.html log.html'
    // On failure, continue the pipeline execution
    env.COMMIT_HASH = 'NONE'
    if (env.OCI_IMAGE_REVISION ==~ /[a-f0-9]{40}/) {
      env.COMMIT_HASH = env.OCI_IMAGE_REVISION
    } else if (params.IMG_URL) {
      def match = params.IMG_URL =~ /commit_([a-f0-9]{40})/
      if (match) {
        env.COMMIT_HASH = match[0][1]
      }
    }
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
        mv -f *.txt *.png *.jpeg *.mp4 *.mkv *.wav output.xml report.html log.html $testname/ || true
      """
    }
  }
}

////////////////////////////////////////////////////////////////////////////////

pipeline {
  agent none
  options {
    buildDiscarder(logRotator(numToKeepStr: '1000'))
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
        stage('Checkout') {
          steps {
            deleteDir()
            script {
              if (params.USE_FLAKE_PINNED_CI_TEST) {
                def pinned_src = sh_ret_out("cat ${CI_TEST_PINNED_SOURCE_FILE}")
                println("Using flake-pinned ci-test-automation source: ${pinned_src}")
                sh """
                  if [ ! -d "${pinned_src}/Robot-Framework/test-suites" ]; then
                    echo "ERROR: invalid ci-test-automation source path '${pinned_src}'"
                    exit 1
                  fi
                  cp -r "${pinned_src}/." .
                  chmod -R u+w .
                """
              } else {
                checkout scmGit(
                  branches: [[name: "${params.CI_TEST_REPO_BRANCH}"]],
                  userRemoteConfigs: [[url: "${params.CI_TEST_REPO_URL}"]]
                )
              }
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
            }
          }
        }
        stage('Verify provenance') {
          steps {
            script {
              def provenance_path
              def sig_path
              if (params.OCI_IMAGE_REF) {
                def discovery = readJSON(
                  text: sh_ret_out("oras discover --format json '${params.OCI_IMAGE_REF}'")
                )
                def referrer = discovery.referrers?.find { it.artifactType == IN_TOTO_MEDIA_TYPE }
                def provenanceRef = referrer?.reference
                if (!provenanceRef && referrer?.digest) {
                  provenanceRef = "${parse_oci_reference(params.OCI_IMAGE_REF).repository}@${referrer.digest}"
                }
                if (!provenanceRef) {
                  error("Unable to discover provenance referrer for OCI image '${params.OCI_IMAGE_REF}'")
                }
                def pullResult = oras_pull_json(provenanceRef, TMP_IMG_DIR)
                provenance_path = find_oci_pull_file(pullResult, IN_TOTO_MEDIA_TYPE)
                sig_path = find_oci_pull_file(pullResult, DETACHED_SIGNATURE_MEDIA_TYPE)
                if (!provenance_path || !sig_path) {
                  error("Unable to derive provenance files from OCI referrer '${provenanceRef}'")
                }
              } else {
                def split = split_img_url(params.IMG_URL)
                def artifacts_url = split["artifacts_url"]
                def target = split["target_name"]
                def provenance_url = "${artifacts_url}/${target}/attestations/provenance.json"
                def signature_url = "${provenance_url}.sig"
                println("provenance_url: ${provenance_url}")
                provenance_path = run_wget(provenance_url, TMP_IMG_DIR)
                sig_path = run_wget(signature_url, TMP_IMG_DIR)
              }
              sh "policy-checker ${provenance_path} --sig ${sig_path} --policy /etc/jenkins/provenance-trust-policy.yaml"
            }
          }
        }
        stage('Image download') {
          steps {
            script {
              def img_path
              def sig_path
              if (params.OCI_IMAGE_REF) {
                def pullResult = oras_pull_json(params.OCI_IMAGE_REF, TMP_IMG_DIR)
                img_path = find_oci_pull_file(pullResult, IMAGE_MEDIA_TYPE)
                sig_path = find_oci_pull_file(pullResult, DETACHED_SIGNATURE_MEDIA_TYPE)
                if (!img_path || !sig_path) {
                  error("Unable to derive image files from OCI image '${params.OCI_IMAGE_REF}'")
                }
              } else {
                img_path = run_wget(params.IMG_URL, TMP_IMG_DIR)
                def split = split_img_url(params.IMG_URL)
                def artifacts_url = split["artifacts_url"]
                def img_relpath = split["img_relpath"]
                def target = split["target_name"]
                def sig_url = "${artifacts_url}/${target}/${img_relpath}.sig"
                sig_path = run_wget(sig_url, TMP_IMG_DIR)
              }
              println "Downloaded image to workspace: ${img_path}"
              println "Downloaded SLSA signature file to workspace: ${sig_path}"
              sh "verify-signature image ${img_path} ${sig_path}"
              // flash-script handles .zst natively; pass the original download path.
              env.FLASH_INPUT_PATH = img_path
              println "Flash input: ${env.FLASH_INPUT_PATH}"
            }
          }
        }
        stage('Flash') {
          steps {
            script {
              // Determine mount commands
              if(env.TARGET.contains("microchip-icicle-")) {
                def muxport = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usb_sd_mux_port')
                env.MOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} host; sleep 10"
                env.UNMOUNT_CMD = "/run/wrappers/bin/sudo usbsdmux ${muxport} dut"
              } else {
                def serial = get_test_conf_property(CONF_FILE_PATH, env.DEVICE_NAME, 'usbhub_serial')
                env.MOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 0 -s ${serial}; sleep 10"
                env.UNMOUNT_CMD = "/run/wrappers/bin/sudo AcronameHubCLI -u 1 -s ${serial}; sleep 10"
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
              def ghafFlakeRef = utils.resolve_ghaf_flake_ref(params.GHAF_FLAKE_REF, params.IMG_URL, env.OCI_SOURCE_REF)
              if (!ghafFlakeRef) {
                if (params.OCI_IMAGE_REF) {
                  error("Missing GHAF_FLAKE_REF and unable to derive it from OCI image '${params.OCI_IMAGE_REF}'")
                }
                error("Missing GHAF_FLAKE_REF and unable to derive Ghaf commit from IMG_URL '${params.IMG_URL}'")
              }
              env.GHAF_FLAKE_REF = ghafFlakeRef
              println "Building flash-script from GHAF_FLAKE_REF: ${ghafFlakeRef}"
              def flashScriptPath = sh_ret_out(
                "nix build --no-link --print-out-paths '${ghafFlakeRef}#packages.x86_64-linux.flash-script'"
              )
              // flash-script validates /dev/sdX format; resolve the by-id symlink
              def resolved_dev = sh_ret_out("/run/wrappers/bin/sudo readlink -f ${dev}")
              sh "/run/wrappers/bin/sudo ${flashScriptPath}/bin/flash-script -d ${resolved_dev} -i ${env.FLASH_INPUT_PATH} -f"
              // Unmount
              sh "${env.UNMOUNT_CMD}"
              sh """
                if /run/wrappers/bin/sudo test -L ${dev}; then
                  echo "Symlink ${dev} was found. Failed to unmount target USB disk from test agent."
                  exit 1
                fi
              """
            }
          }
        }
        stage('Run Ghaf-installer') {
          when { expression { env.TARGET.contains("installer") } }
          steps {
            script {
              println "Run ghaf-installer"
              ghaf_robot_test('installer')
              println "Disconnect SSD from the laptop"
              sh "${env.MOUNT_CMD}"
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
        stage('Regression test') {
          when { expression { env.BOOT_PASSED == 'true' && env.TESTSET.contains('_regression_')} }
          steps {
            script {
              ghaf_robot_test('regression')
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
                'Robot-Framework/test-suites/**/*.jpeg, ' +
                'Robot-Framework/test-suites/**/*.mp4, ' +
                'Robot-Framework/test-suites/**/*.mkv, ' +
                'Robot-Framework/test-suites/**/*.wav, ' +
                'Robot-Framework/test-suites/**/*.txt'
              archiveArtifacts allowEmptyArchive: true, artifacts: test_artifacts
            }
            sh "rm -rf ${TMP_IMG_DIR} || true"
          }
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
