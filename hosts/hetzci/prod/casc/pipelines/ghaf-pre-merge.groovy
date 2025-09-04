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
  [ target: "packages.x86_64-linux.system76-darp11-b-debug",
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
  agent { label 'built-in' }
  options {
    buildDiscarder(logRotator(numToKeepStr: '100'))
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
          // https://www.jenkins.io/doc/pipeline/steps/params/scmgit/#scmgit
          // https://github.com/KostyaSha/github-integration-plugin/blob/master/docs/Configuration.adoc
          checkout scmGit(
            userRemoteConfigs: [[
              url: REPO_URL,
              name: 'pr_origin',
              // Below, we set two git remotes: 'pr_origin' and 'origin'
              // We use '/merge' in pr_origin to build the PR as if it was
              // merged to the PR target branch GITHUB_PR_TARGET_BRANCH.
              // To build the PR head (without merge) you would replace
              // '/merge' with '/head' in the pr_origin remote. We also
              // need to set the 'origin' remote to be able to compare
              // the PR changes against the correct target.
              refspec: '+refs/pull/${GITHUB_PR_NUMBER}/merge:refs/remotes/pr_origin/pull/${GITHUB_PR_NUMBER}/merge +refs/heads/*:refs/remotes/origin/*',
            ]],
            branches: [[name: 'pr_origin/pull/${GITHUB_PR_NUMBER}/merge']],
            extensions: [
              [$class: 'WipeWorkspace'],
              // We use the 'changelogToBranch' extension to correctly
              // show the PR changed commits in Jenkins changes.
              // References:
              // https://issues.jenkins.io/browse/JENKINS-26354
              // https://javadoc.jenkins.io/plugin/git/hudson/plugins/git/extensions/impl/ChangelogToBranch.html
              changelogToBranch (
                options: [
                  compareRemote: 'origin',
                  compareTarget: "${GITHUB_PR_TARGET_BRANCH}"
                ]
              )
            ],
          )
          script {
            sh 'git fetch pr_origin pull/${GITHUB_PR_NUMBER}/head:PR_head'
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
            MODULES.utils.set_github_commit_status("Pending", "pending", env.TARGET_COMMIT)
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
        MODULES.utils.set_github_commit_status("Successful", "success", env.TARGET_COMMIT)
      }
    }
    unsuccessful {
      script {
        MODULES.utils.set_github_commit_status("Failure", "failure", env.TARGET_COMMIT)
      }
    }
  }
}
