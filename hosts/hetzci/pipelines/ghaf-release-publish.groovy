#!/usr/bin/env groovy

def WORKDIR  = 'checkout'

properties([
  parameters([
    string(name: 'GHAF_VERSION', defaultValue: '', description: '''
      Ghaf release tag or version name used to identify the release in the archive. Example: 'ghaf-25.12.1'
      '''.stripIndent()),
    string(name: 'ARTIFACTS_URL', defaultValue: '', description: '''
      Specify the artifacts URL from where the release artifacts will be read.
      If left empty, uses the current latest artifacts from the 'ghaf-release-candidate' pipeline.
      Example:
      'https://ci-release.vedenemo.dev/artifacts/ghaf-release-candidate/20251210_081817797-commit_28fb2bdcbb558d02c33b01ef25a2250ff3fdc479/'
      '''.stripIndent()),
    string(name: 'BUCKET', defaultValue: null, description: '''
      Override the object storage bucket to push to, leave empty to select automatically.
      '''.stripIndent()),
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
            def adir = "/var/lib/jenkins/artifacts/ghaf-release-candidate"
            // By default, take the release artifacts from the newest subdir directly under ${adir}
            env.ARTIFACTS_DIR = sh(script: "ls -dt1 ${adir}/*/ | head -n1", returnStdout:true).trim()
            // If params.ARTIFACTS_URL is defined, parse the artifacts dir from the given string instead
            if (params.ARTIFACTS_URL) {
              // Parse out the ARTIFACTS_DIR from the ARTIFACTS_URL
              // Match e.g. 20251210_112231771-commit_28fb2bdcbb558d02c33b01ef25a2250ff3fdc479
              def match = params.ARTIFACTS_URL =~ /(\d{8}_\d{9}-commit_[0-9a-f]{40})/
              if(match) {
                env.ARTIFACTS_DIR = "${adir}/${match.group(1)}/"
                match = null // https://stackoverflow.com/questions/40454558
                println("Parsed ARTIFACTS_DIR from params.ARTIFACTS_URL")
              } else {
                error("Unexpected ARTIFACTS_URL: ${params.ARTIFACTS_URL}")
              }
            }
            println("Using ARTIFACTS_DIR: ${env.ARTIFACTS_DIR}")
            stage("Check artifacts") {
              sh """
                if [ ! -d "$ARTIFACTS_DIR" ]; then
                  echo "Error: invalid artifacts_dir: '$ARTIFACTS_DIR'"
                  exit 1
                fi
                tree --noreport "$ARTIFACTS_DIR"
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
            def cachix_cache = env.CI_ENV == "release" ? "ghaf-release" : "ghaf-dev"
            stage("Cachix pin") {
              withCredentials([string(credentialsId: 'cachix-auth-token', variable: 'TOKEN')]) {
                env.CACHIX_AUTH_TOKEN="$TOKEN".trim()
                sh """
                  find "$ARTIFACTS_DIR" -type l -iname "otapin.*" | while read -r linkname; do
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
            stage("Archive") {
              withCredentials([
                string(credentialsId: 'jenkins_archive_access_key', variable: 'ACCESS_KEY'),
                string(credentialsId: 'jenkins_archive_secret_key', variable: 'SECRET_KEY')
              ]) {
                env.ACCESS_KEY="$ACCESS_KEY".trim()
                env.SECRET_KEY="$SECRET_KEY".trim()
                if (params.BUCKET == null) {
                  env.BUCKET=(env.CI_ENV == 'release' ? 'ghaf-artifacts' : 'ghaf-artifacts-dev')
                } else {
                  env.BUCKET = params.BUCKET
                }
                sh """
                  archive-ghaf-release -a "$ARTIFACTS_DIR" -t "${params.GHAF_VERSION}"
                """
              }
            }
          }
        }
      }
    }
  }
}
