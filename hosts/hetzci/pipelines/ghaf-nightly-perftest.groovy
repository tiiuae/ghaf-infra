#!/usr/bin/env groovy

@Library('ghafInfra') _

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def PIPELINE = [:]

def TARGETS = [
  [ target: "packages.x86_64-linux.intel-laptop-debug",
    tests: [
      [
        test_target: "lenovo-x1-carbon-gen11-debug",
        testset: '_relayboot_perf_',
      ],
      [
        test_target: "system76-darp11-b-debug",
        testset: '_relayboot_perf_',
      ],
    ],
  ],
  [ target: "packages.x86_64-linux.intel-laptop-low-mem-debug",
    tests: [[
      test_target: "dell-latitude-7330-debug",
      testset: '_relayboot_perf_',
    ]],
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
  [ target: "packages.x86_64-linux.intel-laptop-storeDisk-debug-installer",
    tests: [[
      test_target: "system76-darp11-b-storeDisk-debug-installer",
      testset: '_relayboot_perf_',
    ]],
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
            githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
            parameters([
              booleanParam(name: 'SET_TESTAGENT_HOST', defaultValue: false, description: 'Set true if TESTAGENT_HOST is chosen manually.'),
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
            ]),
            pipelineTriggers([
              cron(env.CI_ENV == 'prod' ? '0 0 * * *' : '')
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
            if (params.SET_TESTAGENT_HOST && params.TESTAGENT_HOST) {
              PIPELINE = pipelineExecution.create_pipeline(TARGETS, params.TESTAGENT_HOST, null, [
                parallel_tests: false,
              ])
            } else {
              PIPELINE = pipelineExecution.create_pipeline(TARGETS, env.CI_ENV, null, [
                parallel_tests: false,
              ])
            }
          }
        }
      }
    }
    stage('Build') {
      steps {
        script {
          PIPELINE.each { key, value ->
            value()
          }
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
