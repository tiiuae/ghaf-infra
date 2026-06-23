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
        device_tag: 'lenovo-x1',
        variant: 'debug',
        testset: '_relayboot_pre-merge_',
      ],
      [
        device_tag: 'darter-pro',
        variant: 'debug',
        testset: '_relayboot_pre-merge_',
      ],
    ],
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
  agent none
  options {
    buildDiscarder(logRotator(numToKeepStr: '100'))
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
            if (!params.GITHUB_PR_NUMBER) {
              error('Missing GITHUB_PR_NUMBER')
            }
          }
          script {
            checkoutUtils.checkout_github_pr_merge(REPO_URL, params.GITHUB_PR_NUMBER)
            env.TARGET_COMMIT = sh(
              script: "git rev-parse refs/remotes/pr_origin/pull/${params.GITHUB_PR_NUMBER}/head",
              returnStdout: true
            ).trim()
            println "TARGET_COMMIT: ${env.TARGET_COMMIT}"
          }
        }
      }
    }
    stage('Setup') {
      agent { label 'built-in' }
      steps {
        dir(artifactSupport.controller_workdir()) {
          script {
            if (params.SET_PR_STATUS) {
              pipelineExecution.set_github_commit_status("Manual trigger: pending", "pending", env.TARGET_COMMIT)
            }
            def pr_href = "<a href=\"${REPO_URL}/pull/${params.GITHUB_PR_NUMBER}\">🧩 PR#${params.GITHUB_PR_NUMBER}</a>"
            artifactSupport.append_to_build_description(pr_href)
            def merge_commit = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
            // The downstream hw-test job needs the PR merge ref as well as the
            // merge SHA, otherwise it cannot refetch GitHub's synthetic merge commit.
            def normalizedRepoUrl = REPO_URL.replaceAll('/+$', '')
            def merge_flake_ref = "git+${normalizedRepoUrl}?ref=refs/pull/${params.GITHUB_PR_NUMBER}/merge&rev=${merge_commit}"
            PIPELINE = pipelineExecution.create_pipeline(TARGETS, null, merge_flake_ref)
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
        artifactSupport.clean_controller_workdir()
      }
    }
    success {
      script {
        if (params.SET_PR_STATUS) {
          node('built-in') {
            pipelineExecution.set_github_commit_status("Manual trigger: success", "success", env.TARGET_COMMIT)
          }
        }
      }
    }
    unsuccessful {
      script {
        if (params.SET_PR_STATUS) {
          node('built-in') {
            pipelineExecution.set_github_commit_status("Manual trigger: failure", "failure", env.TARGET_COMMIT)
          }
        }
      }
    }
  }
}
