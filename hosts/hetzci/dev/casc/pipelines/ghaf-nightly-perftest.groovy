#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

def TARGETS = [
  [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7330-debug",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_perf_',
  ],
  [ target: "packages.x86_64-linux.system76-darp11-b-debug",
    testset: '_relayboot_perf_',
  ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    [
      $class: 'ChoiceParameter',
      name: 'TESTAGENT_HOST',
      choiceType: 'PT_RADIO',
      description: '''
        Select the testagent-host. This parameter allows specifying the exact testagent in case Jenkins controller is
        connected with multiple agents.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['dev','prod','release']"
        ]
      ]
    ]
  ])
])
pipeline {
  agent { label 'built-in' }
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
            if (params.TESTAGENT_HOST) {
              PIPELINE = MODULES.utils.create_pipeline(TARGETS, params.TESTAGENT_HOST)
            } else {
              PIPELINE = MODULES.utils.create_pipeline(TARGETS, 'dev')
            }
          }
        }
      }
    }
    stage('Build') {
      steps {
        dir(WORKDIR) {
          script {
            PIPELINE.each { key, value ->
              value()
            }
          }
        }
      }
    }
  }
}
