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
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug'),
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer'),
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug_sysupdate', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-sysupdate'),
    booleanParam(name: 'dell_latitude_7230_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7230-debug'),
    booleanParam(name: 'dell_latitude_7330_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7330-debug'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-agx-debug'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-nx-debug'),
    booleanParam(name: 'system76_darp11_b_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-debug'),
    booleanParam(name: 'system76_darp11_b_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-debug-installer'),
    booleanParam(name: 'system76_darp11_b_storeDisk_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-storeDisk-debug'),
    booleanParam(name: 'system76_darp11_b_storeDisk_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-storeDisk-debug-installer'),
    booleanParam(name: 'intel_laptop_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-debug'),
    booleanParam(name: 'intel_laptop_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-debug-installer'),
    booleanParam(name: 'intel_laptop_storeDisk_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-storeDisk-debug'),
    booleanParam(name: 'intel_laptop_storeDisk_debug_installer', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-storeDisk-debug-installer'),
    booleanParam(name: 'intel_laptop_low_mem_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.intel-laptop-low-mem-debug'),
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
            if (params.lenovo_x1_carbon_gen11_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug", uefisign: params.UEFISIGN, testset: params.TESTSET, test_secboot: params.SECUREBOOT ])
            }
            if (params.lenovo_x1_carbon_gen11_debug_installer) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer", uefisigniso: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.lenovo_x1_carbon_gen11_debug_sysupdate) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-sysupdate", sysupdate: true, uefisign: params.UEFISIGN, testset: params.TESTSET ])
            }
            if (params.dell_latitude_7230_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7230-debug", testset: null ])
            }
            if (params.dell_latitude_7330_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7330-debug", testset: null ])
            }
            if (params.nvidia_jetson_orin_agx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64", uefisign: params.UEFISIGN, testset: params.TESTSET ])
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
            if (params.system76_darp11_b_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-debug", uefisign: params.UEFISIGN, testset: params.TESTSET  ])
            }
            if (params.system76_darp11_b_debug_installer) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-debug-installer", uefisigniso: params.UEFISIGN, testset: params.TESTSET  ])
            }
            if (params.system76_darp11_b_storeDisk_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-storeDisk-debug", uefisign: params.UEFISIGN, testset: params.TESTSET  ])
            }
            if (params.system76_darp11_b_storeDisk_debug_installer) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-storeDisk-debug-installer", uefisigniso: params.UEFISIGN, testset: params.TESTSET  ])
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
                  ],
                ],
              ))
            }
            if (params.intel_laptop_debug_installer) {
              TARGETS.push(addExplicitTests(
                [ target: "packages.x86_64-linux.intel-laptop-debug-installer", uefisigniso: params.UEFISIGN ],
                [[
                  device_tag: 'lenovo-x1',
                  variant: 'debug-installer',
                ]],
              ))
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
