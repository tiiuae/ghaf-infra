#!/usr/bin/env groovy

@Library('ghafInfra') _

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def PIPELINE = [:]

def ALL_RELEASE_TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    no_image: true, testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    uefisign: true, build_otapin: true, sbom: true,
    tests: [
      [
        device_tag: 'lenovo-x1',
        variant: 'debug',
        testset: '_relayboot_bat_',
      ],
      [
        device_tag: 'darter-pro',
        variant: 'debug',
        testset: '_relayboot_bat_',
      ],
    ],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug-installer",
    testset: null, uefisigniso: true, sbom: true,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_bat_', sbom: true,
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_bat_', sbom: true,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_bat_', sbom: true,
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_bat_', sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer",
    testset: null, uefisigniso: true, sbom: true,
  ],
]

def LAPTOP_RELEASE_TARGETS = [
  [ target: "packages.x86_64-linux.doc",
    no_image: true, testset: null, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    uefisign: true, build_otapin: true, sbom: true,
    tests: [
      [
        device_tag: 'lenovo-x1',
        variant: 'debug',
        testset: '_relayboot_bat_',
      ],
      [
        device_tag: 'darter-pro',
        variant: 'debug',
        testset: '_relayboot_bat_',
      ],
    ],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-debug-installer",
    testset: null, uefisigniso: true, sbom: true,
  ],
  [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer",
    testset: null, uefisigniso: true, sbom: true,
  ],
]

def MINIMAL_BUILD_TARGETS = [
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    testset: null, provenance: false,
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: null, provenance: false,
  ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    [
      $class: 'ChoiceParameter',
      name: 'RELEASE_TARGETS_SET',
      choiceType: 'PT_RADIO',
      description: '''
        Select a release target set. Build fails if unselected.'''.stripIndent(),
      script: [
        $class: 'GroovyScript',
        script: [
          classpath: [],
          sandbox: true,
          script: "return ['All targets','Only laptop targets','Minimal build targets (cache warming)']"
        ]
      ]
    ],
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)')
  ])
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
            checkoutUtils.checkout_remote_ref(REPO_URL, params.GITREF)
          }
        }
      }
    }
    stage('Setup') {
      agent { label 'built-in' }
      steps {
        dir(artifactSupport.controller_workdir()) {
          script {
            if (params.RELEASE_TARGETS_SET.contains('All targets')) {
              println('All release targets selected')
              PIPELINE = pipelineExecution.create_pipeline(ALL_RELEASE_TARGETS)
            } else if (params.RELEASE_TARGETS_SET.contains('Only laptop targets')){
              println('Only laptop release targets selected')
              PIPELINE = pipelineExecution.create_pipeline(LAPTOP_RELEASE_TARGETS)
            } else if (params.RELEASE_TARGETS_SET.contains('Minimal build targets')){
              println('Minimal build targets selected')
              PIPELINE = pipelineExecution.create_pipeline(MINIMAL_BUILD_TARGETS)
            } else {
              error('Release targets pre-set was not selected')
            }
          }
        }
      }
    }
    stage('Build and test') {
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
