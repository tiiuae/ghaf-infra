#!/usr/bin/env groovy

def WORKDIR  = 'checkout'

properties([
  parameters([
    string(name: 'GHAF_VERSION', defaultValue: '', description: 'Ghaf release tag or version name used to identify the release in the archive, e.g.: ghaf-25.12.1')
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
    stage('Setup') {
      steps {
        dir(WORKDIR) {
          script {
            if (!params.GHAF_VERSION) {
              error('Missing GHAF_VERSION parameter')
            }
            def build_workspace = "${env.WORKSPACE}/../ghaf-release-candidate/checkout"
            stage("Log ghaf commit") {
              sh """
                git --git-dir=${build_workspace}/.git log -n1 --pretty=format:'%H' 2>/dev/null
              """
            }
            stage("Check artifacts") {
              sh """
                if [ ! -f ${build_workspace}/artifacts_dir ]; then
                  echo "Error: missing file: ${build_workspace}/artifacts_dir"
                  exit 1
                fi
                artifacts_dir=\$(<${build_workspace}/artifacts_dir)
                if [ -z "\$artifacts_dir" ] || [ ! -d "\$artifacts_dir" ]; then
                  echo "Error: invalid artifacts_dir: '\$artifacts_dir'"
                  exit 1
                fi
                tree --noreport "\$artifacts_dir"
              """
            }
          }
        }
      }
    }
    stage('OTA pin') {
      steps {
        dir(WORKDIR) {
          script {
            def build_workspace = "${env.WORKSPACE}/../ghaf-release-candidate/checkout"
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
    stage('Archive release') {
      steps {
        dir(WORKDIR) {
          script {
            def build_workspace = "${env.WORKSPACE}/../ghaf-release-candidate/checkout"
            stage("Archive") {
              withCredentials([
                string(credentialsId: 'jenkins_archive_access_key', variable: 'ACCESS_KEY'),
                string(credentialsId: 'jenkins_archive_secret_key', variable: 'SECRET_KEY')
              ]) {
                env.ACCESS_KEY="$ACCESS_KEY".trim()
                env.SECRET_KEY="$SECRET_KEY".trim()
                env.BUCKET=(env.CI_ENV == 'release' ? 'ghaf-artifacts' : 'ghaf-artifacts-dev')
                sh """
                  artifacts_dir=\$(<${build_workspace}/artifacts_dir)
                  /etc/jenkins/archive-ghaf-release.sh -a "\$artifacts_dir" -t ${params.GHAF_VERSION}
                """
              }
            }
          }
        }
      }
    }
  }
}
