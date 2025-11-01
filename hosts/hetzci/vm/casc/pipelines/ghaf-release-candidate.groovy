#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

def ALL_RELEASE_TARGETS = [
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

def LAPTOP_RELEASE_TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug",
    testset: '_relayboot_bat_',
  ],
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug-installer",
    testset: null,
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
    [
      $class: 'ChoiceParameter',
      name: 'RELEASE_TARGETS_SET',
      choiceType: 'PT_RADIO',
      description: '''
        Select release targets pre-set between all targets or only laptop(x1, darp) targets. Selection is a requirement! '''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['All targets','Only laptop targets']"
        ]
      ]
    ],
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)')
  ])
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
            if (params.RELEASE_TARGETS_SET.contains('All targets')) {
              println('All release targets selected!')
              PIPELINE = MODULES.utils.create_pipeline(ALL_RELEASE_TARGETS)
            } else if (params.RELEASE_TARGETS_SET.contains('Only laptop targets')){
              println('Only laptop release targets selected!')
              PIPELINE = MODULES.utils.create_pipeline(LAPTOP_RELEASE_TARGETS)
            } else {
              error('Release targets pre-set was not selected!')
            }
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
    stage('Build OTA pin') {
      steps {
        dir(WORKDIR) {
          script {
            OTA_TARGETS.each {
              stage("Build ${it.target}") {
                sh """
                  nixos-rebuild build --fallback --flake .#${it.target}
                  mv result otapin.${it.target}
                """
              }
            }
          }
        }
      }
    }
  }
}
