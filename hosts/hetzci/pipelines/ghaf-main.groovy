#!/usr/bin/env groovy

@Library('ghafInfra') _

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def PIPELINE = [:]

def TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    no_image: true, testset: null,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    tests: [
      [
        test_target: "lenovo-x1-carbon-gen11-debug",
        testset: '_relayboot_bat_',
      ],
      [
        test_target: "system76-darp11-b-debug",
        testset: '_relayboot_bat_',
      ],
    ],
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7230-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-low-mem-debug",
    tests: [[
      test_target: "dell-latitude-7330-debug",
      testset: '_relayboot_bat_',
    ]],
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx64-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx64-debug-from-x86_64",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_bat_',
  ],
]

properties([
  disableConcurrentBuilds(abortPrevious: true),
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL)
])
pipeline {
  agent none
  triggers {
    githubPush()
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  stages {
    // githubPush() trigger requires checkout to be done at least once to
    // activate the trigger. Therefore, the 'Checkout' stage needs to happen
    // before 'Reload only', otherwise this pipeline would never trigger
    // on githubPush().
    stage('Checkout') {
      agent { label 'built-in' }
      steps {
        dir(artifactUtils.controller_workdir()) {
          script {
            checkoutUtils.checkout_remote_ref(REPO_URL, 'main')
          }
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
    stage('Setup') {
      agent { label 'built-in' }
      steps {
        dir(artifactUtils.controller_workdir()) {
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
