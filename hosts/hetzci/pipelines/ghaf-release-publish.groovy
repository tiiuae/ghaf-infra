#!/usr/bin/env groovy

def WORKDIR  = 'checkout'

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
    stage('OTA pin') {
      steps {
        dir(WORKDIR) {
          script {
            def build_workspace = "${env.WORKSPACE}/../ghaf-release-candidate/checkout"
            stage("Log ghaf commit") {
              sh """
                git --git-dir=${build_workspace}/.git log -n1 --pretty=format:'%H' 2>/dev/null
              """
            }
            def cachix_cache = env.CI_ENV == "release" ? "ghaf-release" : "ghaf-dev"
            stage("Cachix pin") {
              withCredentials([string(credentialsId: 'cachix-auth-token', variable: 'TOKEN')]) {
                env.CACHIX_AUTH_TOKEN="$TOKEN".trim()
                sh """
                  find ${build_workspace} -type l -iname "otapin.*" | while read -r linkname; do
                    target="\${linkname#*otapin.}"
                    cachix push ${cachix_cache} \$(readlink -f \$linkname)
                    cachix pin -v ${cachix_cache} \${target} \$(readlink -f \$linkname) --keep-revisions 2
                  done
                """
              }
            }
          }
        }
      }
    }
  }
}
