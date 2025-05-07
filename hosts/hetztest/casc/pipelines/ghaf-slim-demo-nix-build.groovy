#!/usr/bin/env groovy

def REPO_URL = 'https://github.com/tiiuae/ghaf-slim-demo/'
def WORKDIR  = 'checkout'

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITREF', defaultValue: 'main', description: 'Git reference (Commit/Branch/Tag)'),
    booleanParam(name: 'RELOAD_ONLY', defaultValue: true, description: 'Reload pipeline configuration without running any other stages')
  ])
])
pipeline {
  agent { label 'built-in' }
  options {
    buildDiscarder(logRotator(numToKeepStr: '100'))
  }
  stages {
    stage('Reload only') {
      when { expression { !params || params.RELOAD_ONLY } }
      steps {
        script {
          currentBuild.result = 'ABORTED'
          println 'Pipeline configuration reloaded'
          env.ABORTED = 'true'
        }
      }
    }
    stage('Build') {
      when { expression { env.ABORTED != 'true' } }
      steps {
        dir(WORKDIR) {
          checkout scmGit(
            branches: [[name: params.GITREF]],
            extensions: [[$class: 'WipeWorkspace']],
            userRemoteConfigs: [[url: REPO_URL]]
          )
          script {
            sh '''
              nix build .#checks.x86_64-linux.package-doc
            '''
          }
        }
      }
    }
  }
}