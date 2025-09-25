#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

def RELEASE_TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer",
    testset: null,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
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

def OTA_TARGETS = [
  [ target: "lenovo-x1-carbon-gen11-debug" ],
  [ target: "system76-darp11-b-debug" ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)'),
  ])
])
pipeline {
  agent { label 'built-in' }
  triggers {
    githubPush()
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '5'))
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
            branches: [[name: params.GITREF]],
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
            PIPELINE = MODULES.utils.create_pipeline(RELEASE_TARGETS)
          }
        }
      }
    }
    stage('Build and test') {
      steps {
        dir(WORKDIR) {
          script {
            catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
              parallel PIPELINE
            }
          }
        }
      }
    }
    stage('OTA pin') {
      steps {
        dir(WORKDIR) {
          script {
            withCredentials([string(credentialsId: 'cachix-auth-token', variable: 'TOKEN')]) {
              env.CACHIX_AUTH_TOKEN="$TOKEN".trim()
              OTA_TARGETS.each {
                stage("Pin ${it.target}") {
                  sh """
                    nixos-rebuild build --fallback --flake .#${it.target}
                    cachix push ghaf-release \$(readlink -f result)
                    cachix pin -v ghaf-release ${it.target} \$(readlink -f result) --keep-revisions 2
                  """
                }
              }
            }
          }
        }
      }
    }
  }
}
