#!/usr/bin/env groovy

@Library('ghafInfra') _

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def PIPELINE = [:]

def TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    no_image: true, testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    uefisign: true, sbom: true,
    tests: [
      [
        test_target: "lenovo-x1-carbon-gen11-debug",
        testset: '_relayboot_regression_',
        test_secboot: true,
      ],
      [
        test_target: "system76-darp11-b-debug",
        testset: '_relayboot_regression_',
      ],
    ],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug-installer",
    uefisigniso: true, sbom: true,
    tests: [[
      test_target: "lenovo-x1-carbon-gen11-debug-installer",
      testset: '_relayboot_regression_',
    ]],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer",
    uefisigniso: true, sbom: true,
    tests: [[
      test_target: "system76-darp11-b-storeDisk-debug-installer",
      testset: '_relayboot_regression_',
    ]],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-release",
    testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-release-installer",
    testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-low-mem-debug",
    sbom: true,
    tests: [[
      test_target: "dell-latitude-7330-debug",
      testset: '_relayboot_regression_',
    ]],
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx64-debug",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx64-debug-from-x86_64",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_regression_', uefisign: true, sbom: true,
  ],
  [ target: "packages.x86_64-linux.generic-x86_64-debug",
    testset: null, sbom: true,
  ],
  [ target: "packages.aarch64-linux.nxp-imx8mp-evk-debug",
    testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug",
    testset: null, sbom: true,
  ],
]

pipeline {
  agent none
  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  stages {
    stage('Set properties') {
      agent { label 'built-in' }
      steps {
        script {
          properties([
            disableConcurrentBuilds(abortPrevious: true),
            githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
            pipelineTriggers([
              cron(env.CI_ENV == 'prod' ? '0 20 * * *' : '')
            ]),
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
            checkoutUtils.checkout_remote_ref(REPO_URL, 'main')
          }
        }
      }
    }
    stage('Setup') {
      agent { label 'built-in' }
      steps {
        dir(artifactSupport.controller_workdir()) {
          script {
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
        artifactUtils.clean_controller_workdir()
      }
    }
  }
}
