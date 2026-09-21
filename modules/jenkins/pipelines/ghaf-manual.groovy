#!/usr/bin/env groovy

@Library('ghafInfra') _

def DEFAULT_REPO_URL = 'https://github.com/tiiuae/ghaf/'
def PIPELINE = [:]

properties([
  githubProjectProperty(displayName: ''),
  parameters([
    booleanParam(name: 'UEFISIGN', defaultValue: false, description: 'Enable secure boot signing (for supported targets)'),
    booleanParam(name: 'SECUREBOOT', defaultValue: false, description: 'Run tests also on secureboot enabled hardware, if available'),
    string(name: 'REPO_URL', defaultValue: DEFAULT_REPO_URL, description: 'Git repository URL'),
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)'),
    string(name: 'TESTSET', defaultValue: null, description: 'By default tests are skipped. To run hw-tests, define the target testset here; e.g.: _relayboot_, _relayboot_bat_, _relayboot_pre-merge_, etc.)'),
    string(
      name: 'CUSTOM_GHAF_TARGET',
      defaultValue: '',
      description: 'Additional Ghaf flake target to build.'
    ),
    booleanParam(
      name: 'EXECUTE_ORIN_AGX_FLASH',
      defaultValue: false,
      description: 'Execute a custom Ghaf target ending with -flash-script or -flash-qspi after Build.'
    ),
    booleanParam(name: 'doc', defaultValue: false, description: 'Build target packages.x86_64-linux.doc'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_agx_accelerated_guivm_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-agx-accelerated-guivm-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-agx-debug'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-nx-debug'),
    booleanParam(name: 'intel_laptop_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-debug (generic Intel laptop image replacing Lenovo X1 and Darter Pro debug targets)'),
    booleanParam(name: 'intel_laptop_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-debug-installer (generic Intel laptop installer replacing Lenovo X1 and Darter Pro installer targets)'),
    booleanParam(name: 'intel_laptop_debug_sysupdate', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-debug-sysupdate (generic Intel laptop A/B update image replacing the Lenovo X1 sysupdate target)'),
    booleanParam(name: 'intel_laptop_storeDisk_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-storeDisk-debug (generic Intel laptop storeDisk image replacing the Darter Pro storeDisk debug target)'),
    booleanParam(name: 'intel_laptop_storeDisk_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-storeDisk-debug-installer (generic Intel laptop storeDisk installer replacing the Darter Pro storeDisk installer target)'),
    booleanParam(name: 'intel_laptop_low_mem_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-low-mem-debug (generic Intel laptop low-memory image replacing the Dell Latitude 7330 debug target)'),
    booleanParam(name: 'intel_laptop_low_mem_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-low-mem-debug-installer'),
  ])
])
pipeline {
  agent none
  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  stages {
    stage('Reload only') {
      agent { label 'built-in' }
      when { expression { params && params.RELOAD_ONLY } }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          currentBuild.displayName = "Reloaded pipeline"
          error('Reloading pipeline - aborting other stages')
        }
      }
    }
    stage('Checkout') {
      agent { label 'built-in' }
      steps {
        dir(artifactSupport.controller_workdir()) {
          script {
            checkoutUtils.checkout_remote_ref(params.REPO_URL, params.GITREF)
          }
        }
      }
    }
    stage('Setup') {
      agent { label 'built-in' }
      steps {
        dir(artifactSupport.controller_workdir()) {
          script {
            def TARGETS = []
            def normalizedTestset = params.TESTSET?.trim()
            if (normalizedTestset?.isEmpty()) {
              normalizedTestset = null
            }
            def addExplicitTests = { Map targetConfig, List testMappings ->
              if (!normalizedTestset) {
                return targetConfig
              }
              targetConfig.tests = testMappings.collect { testMapping ->
                def explicitTest = [
                  testset: normalizedTestset,
                ]
                if (testMapping.containsKey('test_target')) {
                  explicitTest.test_target = testMapping.test_target
                }
                if (testMapping.containsKey('device_tag')) {
                  explicitTest.device_tag = testMapping.device_tag
                }
                if (testMapping.containsKey('variant')) {
                  explicitTest.variant = testMapping.variant
                }
                if (testMapping.containsKey('test_secboot')) {
                  explicitTest.test_secboot = testMapping.test_secboot
                }
                return explicitTest
              }
              return targetConfig
            }
            if (params.doc) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.doc", no_image: true, testset: null ])
            }
            if (params.nvidia_jetson_orin_agx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64", uefisign: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_agx_accelerated_guivm_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-accelerated-guivm-debug-from-x86_64",
                  no_image: true, testset: null, provenance: false ])
            }
            if (params.nvidia_jetson_orin_nx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64", uefisign: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_agx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug", uefisign: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_nx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug", uefisign: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.intel_laptop_debug) {
              TARGETS.push(addExplicitTests(
                [ target: "packages.x86_64-linux.intel-laptop-debug", uefisign: params.UEFISIGN ],
                [
                  [
                    device_tag: 'lenovo-x1',
                    variant: 'debug',
                    test_secboot: params.SECUREBOOT,
                  ],
                  [
                    device_tag: 'darter-pro',
                    variant: 'debug',
                    test_secboot: params.SECUREBOOT,
                  ],
                ],
              ))
            }
            if (params.intel_laptop_debug_installer) {
              TARGETS.push(addExplicitTests(
                [ target: "packages.x86_64-linux.intel-laptop-debug-installer", uefisigniso: params.UEFISIGN ],
                [
                  [
                    device_tag: 'lenovo-x1',
                    variant: 'debug-installer',
                  ],
                  [
                    device_tag: 'darter-pro',
                    variant: 'debug-installer',
                  ],
                ],
              ))
            }
            if (params.intel_laptop_debug_sysupdate) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.intel-laptop-debug-sysupdate", sysupdate: true, uefisign: params.UEFISIGN, testset: null ])
            }
            if (params.intel_laptop_storeDisk_debug) {
              TARGETS.push(addExplicitTests(
                [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug", uefisign: params.UEFISIGN ],
                [[
                  device_tag: 'darter-pro',
                  variant: 'storeDisk-debug',
                ]],
              ))
            }
            if (params.intel_laptop_storeDisk_debug_installer) {
              TARGETS.push(addExplicitTests(
                [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer", uefisigniso: params.UEFISIGN ],
                [[
                  device_tag: 'darter-pro',
                  variant: 'storeDisk-debug-installer',
                ]],
              ))
            }
            if (params.intel_laptop_low_mem_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.intel-laptop-low-mem-debug", uefisign: params.UEFISIGN, testset: null ])
            }
            if (params.intel_laptop_low_mem_debug_installer) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.intel-laptop-low-mem-debug-installer", uefisigniso: params.UEFISIGN, testset: null ])
            }
            def customTarget = params.CUSTOM_GHAF_TARGET?.trim()
            if (customTarget) {
              if (customTarget.endsWith('-flash-script') || customTarget.endsWith('-flash-qspi')) {
                TARGETS.push([ target: customTarget, no_image: true, testset: null, provenance: false ])
              } else {
                TARGETS.push([
                  target: customTarget,
                  uefisign: params.UEFISIGN,
                  testset: null,
                  provenance: false,
                ])
              }
            }

            PIPELINE = pipelineExecution.create_pipeline(TARGETS)
          }
        }
      }
    }
    stage('Build') {
      steps {
        script {
          parallel PIPELINE
        }
      }
    }
    stage('Execute Orin AGX flash') {
      agent none
      when { expression { params && params.EXECUTE_ORIN_AGX_FLASH } }
      steps {
        script {
          def flashTarget = params.CUSTOM_GHAF_TARGET?.trim()
          if (!(flashTarget?.endsWith('-flash-script') || flashTarget?.endsWith('-flash-qspi'))) {
            error("EXECUTE_ORIN_AGX_FLASH requires CUSTOM_GHAF_TARGET to end with '-flash-script' or '-flash-qspi'")
          }
          def flashScriptPath
          artifactSupport.with_controller_workspace(artifactSupport.controller_workdir()) {
            flashScriptPath = artifactSupport.run_cmd("nix path-info .#${flashTarget}")
          }
          def deviceInfo = pipelineModel.device_info(flashTarget, false)
            ?: pipelineModel.device_info(null, false, 'orin-agx')
          if (!deviceInfo || !['orin-agx', 'orin-agx-64'].contains(deviceInfo.tag)) {
            error("Unable to resolve Orin AGX device config for flash target '${flashTarget}'")
          }
          // The script is run without --secure-boot below, so do not fall back
          // to a Secure Boot device when the ordinary AGX64 is unavailable.
          def onlineTestagents = nodesByLabel(label: deviceInfo.tag, offline: false)
          if (onlineTestagents.isEmpty()) {
            error("No '${deviceInfo.tag}' test agent is online for '${flashTarget}'")
          }
          node(deviceInfo.tag) {
            env.ORIN_AGX_FLASH_SCRIPT_PATH = flashScriptPath
            def flashGcRootTag = (env.BUILD_TAG ?: "build-${env.BUILD_NUMBER}")
              .replaceAll(/[^A-Za-z0-9_.-]/, '_')
            env.ORIN_AGX_FLASH_GCROOT = "/var/lib/jenkins/gcroots/orin-agx-flash-script-${flashGcRootTag}"
            env.ORIN_AGX_RELAY_NAME = "relay-${deviceInfo.name}"
            def testAgentHost = sh(
              script: 'IFS= read -r host < /proc/sys/kernel/hostname; printf %s "$host"',
              returnStdout: true
            ).trim()
            try {
              sh """
                set -eu
                . /var/lib/jenkins/jenkins.env
                controller_url="\${CONTROLLER:-}"
                controller_host="\${controller_url#*://}"
                controller_host="\${controller_host%%/*}"
                if [ -z "\$controller_host" ]; then
                  echo "Unable to derive Jenkins controller host from CONTROLLER='\$controller_url'"
                  exit 1
                fi
                mkdir -p /var/lib/jenkins/gcroots
                find /var/lib/jenkins/gcroots \
                  -maxdepth 1 \
                  -type l \
                  -name 'orin-agx-flash-script-*' \
                  -mtime +7 \
                  -delete
                NIX_SSHOPTS="-i /run/secrets/ssh_host_ed25519_key -o StrictHostKeyChecking=no" \
                  nix copy \
                    --from ssh://${testAgentHost}@\$controller_host \
                    --no-check-sigs \
                    ${flashScriptPath}
                nix-store --add-root "\$ORIN_AGX_FLASH_GCROOT" \
                  --realise "\$ORIN_AGX_FLASH_SCRIPT_PATH"
              """
              sh """
                set -eu
                curl --fail-with-body --silent --show-error \
                  --request POST \
                  --form "relay=\$ORIN_AGX_RELAY_NAME" \
                  --form "state=ON" \
                  http://127.0.0.1:8000/api/set_state
                sleep 5
              """
              def boardctlOutput = sh(
                script: '''
                  set +e
                  /run/wrappers/bin/sudo \
                    /var/lib/nvidia/Linux_for_Tegra/tools/board_automation/boardctl \
                    -t topo recovery 2>&1
                  echo "BOARDCTL_RC=$?"
                ''',
                returnStdout: true
              ).trim()
              println(boardctlOutput)
              def boardctlRcLine = boardctlOutput.readLines().find { it.startsWith('BOARDCTL_RC=') }
              if (boardctlRcLine == null) {
                error('Unable to read boardctl return code')
              }
              def boardctlRc = boardctlRcLine - 'BOARDCTL_RC='
              if (boardctlRc != '0') {
                error("boardctl failed with return code ${boardctlRc}")
              }
              if (!boardctlOutput.contains('Recovery mode done.')) {
                error("boardctl output did not contain 'Recovery mode done.'")
              }
              timeout(time: 60, unit: 'MINUTES') {
                sh '''
                  set -eu
                  flash_scripts="$(find "${ORIN_AGX_FLASH_SCRIPT_PATH}/bin" -maxdepth 1 -type f -executable)"
                  flash_script_count="$(printf '%s\n' "$flash_scripts" | sed '/^$/d' | wc -l)"
                  if [ "$flash_script_count" -ne 1 ]; then
                    echo "Expected exactly one executable in ${ORIN_AGX_FLASH_SCRIPT_PATH}/bin"
                    printf '%s\n' "$flash_scripts"
                    exit 1
                  fi
                  flash_script="$(printf '%s\n' "$flash_scripts")"
                  /run/wrappers/bin/sudo "$flash_script"
                '''
              }
            } finally {
              sh '''
                curl --fail-with-body --silent --show-error \
                  --request POST \
                  --form "relay=$ORIN_AGX_RELAY_NAME" \
                  --form "state=OFF" \
                  http://127.0.0.1:8000/api/set_state || \
                  echo "Warning: failed to turn off relay $ORIN_AGX_RELAY_NAME"
                rm -f "$ORIN_AGX_FLASH_GCROOT" || true
              '''
            }
          }
        }
      }
    }
  }
  post {
    always {
      script {
        artifactSupport.clean_controller_workdir()
      }
    }
  }
}
