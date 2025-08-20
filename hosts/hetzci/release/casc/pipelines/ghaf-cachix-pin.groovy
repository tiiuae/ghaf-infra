#!/usr/bin/env groovy

import groovy.transform.Field

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def TARGETS = [
  [ target: "lenovo-x1-carbon-gen11-debug"],
]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Tag/Commit/Branch) to cachix pin'),
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
            branches: [[name: params.GITREF]],
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: REPO_URL]]
          )
        }
      }
    }
    stage('Cachix pin') {
      steps {
        dir(WORKDIR) {
          script {
            withCredentials([string(credentialsId: 'cachix-auth-token', variable: 'TOKEN')]) {
              env.CACHIX_AUTH_TOKEN="$TOKEN".trim()
              TARGETS.each {
                stage("Pin ${it.target}") {
                  sh """
                    nixos-rebuild build --flake .#${it.target}
                    cachix push ghaf-dev \$(readlink -f result)
                    cachix pin -v ghaf-dev ${it.target} \$(readlink -f result) --keep-revisions 2
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
