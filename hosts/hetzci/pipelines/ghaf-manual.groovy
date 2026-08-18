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
  }
  post {
    always {
      script {
        artifactSupport.clean_controller_workdir()
      }
    }
  }
}
