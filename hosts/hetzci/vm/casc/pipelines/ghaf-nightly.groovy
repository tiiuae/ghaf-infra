#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

def TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug",
    testset: '_relayboot_gui_regression_',
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer",
    testset: '_relayboot_gui_regression_',
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-release",
    testset: null, uefisign: true,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-release-installer",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-gen11-hardening-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-gen11-hardening-debug-installer",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7230-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7330-debug",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx64-debug",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx64-debug-from-x86_64",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_regression_',
  ],
  [ target: "packages.x86_64-linux.generic-x86_64-debug",
    testset: null,
  ],
  [ target: "packages.aarch64-linux.nxp-imx8mp-evk-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.system76-darp11-b-debug",
    testset: '_relayboot_gui_regression_', uefisign: true,
  ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL)
])
pipeline {
  agent { label 'built-in' }
  triggers {
    cron('0 20 * * *')
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  stages {
    stage('Reload only') {
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
      steps {
        dir(WORKDIR) {
          checkout scmGit(
            branches: [[name: 'main']],
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: REPO_URL]]
          )
        }
      }
    }
    stage('Setup') {
      steps {
        dir(WORKDIR) {
          script {
            MODULES.utils = load "/etc/jenkins/pipelines/modules/utils.groovy"
            PIPELINE = MODULES.utils.create_pipeline(TARGETS)
          }
        }
      }
    }
    stage('Build') {
      steps {
        dir(WORKDIR) {
          script {
            parallel PIPELINE
          }
        }
      }
    }
  }
}
