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
    testset: '_relayboot_pre-merge_',
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7230-debug",
    testset: null,
  ],
  [ target: "packages.x86_64-linux.dell-latitude-7330-debug",
    testset: '_relayboot_pre-merge_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug",
    testset: '_relayboot_pre-merge_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64",
    testset: '_relayboot_pre-merge_',
  ],
  [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug",
    testset: '_relayboot_pre-merge_',
  ],
  [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64",
    testset: '_relayboot_pre-merge_',
  ],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITHUB_PR_NUMBER', defaultValue: '', description: 'Ghaf PR number'),
    booleanParam(name: 'SET_PR_STATUS', defaultValue: true, description: 'Write the commit status in GitHub PR')
  ])
])

pipeline {
  agent { label 'built-in' }
  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
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
            userRemoteConfigs: [[
              url: REPO_URL,
              name: 'pr_origin',
              // Below, we set the git remote: 'pr_origin'.
              // We use '/merge' in pr_origin to build the PR as if it was
              // merged to the PR target branch. To build the PR head (without
              // merge) you would replace '/merge' with '/head'.
              refspec: "+refs/pull/${params.GITHUB_PR_NUMBER}/merge:refs/remotes/pr_origin/pull/${params.GITHUB_PR_NUMBER}/merge",
            ]],
            branches: [[name: "pr_origin/pull/${params.GITHUB_PR_NUMBER}/merge"]],
            extensions: [
              [$class: 'WipeWorkspace'],
            ],
          )
          script {
            sh "git fetch pr_origin pull/${params.GITHUB_PR_NUMBER}/head:PR_head"
            env.TARGET_COMMIT = sh(script: 'git rev-parse PR_head', returnStdout: true).trim()
            println "TARGET_COMMIT: ${env.TARGET_COMMIT}"
          }
        }
      }
    }
    stage('Setup') {
      steps {
        dir(WORKDIR) {
          script {
            MODULES.utils = load "/etc/jenkins/pipelines/modules/utils.groovy"
            if (params.SET_PR_STATUS) {
              MODULES.utils.setBuildStatus("Manual trigger: pending", "pending", env.TARGET_COMMIT)
            }
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
  post {
    success {
      script {
        if (params.SET_PR_STATUS) {
          MODULES.utils.setBuildStatus("Manual trigger: success", "success", env.TARGET_COMMIT)
        }
      }
    }
    unsuccessful {
      script {
        if (params.SET_PR_STATUS) {
          MODULES.utils.setBuildStatus("Manual trigger: failure", "failure", env.TARGET_COMMIT)
        }
      }
    }
  }
}