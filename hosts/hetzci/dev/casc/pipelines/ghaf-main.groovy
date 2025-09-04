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
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7230-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7330-debug",
    testset: '_relayboot_bat_',
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
  [ target: "packages.x86_64-linux.system76-darp11-b-debug",
    testset: '_relayboot_bat_',
  ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL)
])
pipeline {
  agent { label 'built-in' }
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
