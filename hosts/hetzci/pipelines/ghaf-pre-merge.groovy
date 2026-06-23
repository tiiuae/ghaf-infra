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
  // https://www.jenkins.io/doc/pipeline/steps/params/pipelinetriggers/
  pipelineTriggers([
    githubPullRequests(
      spec: '',
      triggerMode: 'HEAVY_HOOKS',
      events: [Open(), commitChanged(), close(), nonMergeable(skip: true)],
      abortRunning: true,
      cancelQueued: true,
      preStatus: false,
      skipFirstRun: false,
      userRestriction: [users: '', orgs: 'tiiuae'],
      repoProviders: [
        githubPlugin(
          repoPermission: 'PULL'
        )
      ]
    )
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
            checkoutUtils.checkout_github_pr_merge(
              REPO_URL,
              env.GITHUB_PR_NUMBER,
              env.GITHUB_PR_TARGET_BRANCH,
              [
                // We use the 'changelogToBranch' extension to correctly
                // show the PR changed commits in Jenkins changes.
                // References:
                // https://issues.jenkins.io/browse/JENKINS-26354
                // https://javadoc.jenkins.io/plugin/git/hudson/plugins/git/extensions/impl/ChangelogToBranch.html
                changelogToBranch(
                  options: [
                    compareRemote: 'origin',
                    compareTarget: "${GITHUB_PR_TARGET_BRANCH}"
                  ]
                )
              ]
            )
            env.TARGET_COMMIT = sh(
              script: 'git rev-parse refs/remotes/pr_origin/pull/${GITHUB_PR_NUMBER}/head',
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
            pipelineExecution.set_github_commit_status("Pending", "pending", env.TARGET_COMMIT)
            def merge_commit = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
            // The downstream hw-test job needs the PR merge ref as well as the
            // merge SHA, otherwise it cannot refetch GitHub's synthetic merge commit.
            def normalizedRepoUrl = REPO_URL.replaceAll('/+$', '')
            def merge_flake_ref = "git+${normalizedRepoUrl}?ref=refs/pull/${GITHUB_PR_NUMBER}/merge&rev=${merge_commit}"
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
        node('built-in') {
          pipelineExecution.set_github_commit_status("Successful", "success", env.TARGET_COMMIT)
        }
      }
    }
    unsuccessful {
      script {
        node('built-in') {
          pipelineExecution.set_github_commit_status("Failure", "failure", env.TARGET_COMMIT)
        }
      }
    }
  }
}
