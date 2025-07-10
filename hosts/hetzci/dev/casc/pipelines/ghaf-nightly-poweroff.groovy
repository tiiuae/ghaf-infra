#!/usr/bin/env groovy

properties([
  githubProjectProperty(displayName: '')
])

def poweroff(String device) {
  def testagent_nodes = nodesByLabel(label: "$device", offline: false)
  if (!testagent_nodes) {
    unstable("No '$device' test agents online")
    return
  }
  def job = build(job: "ghaf-hw-test-manual", propagate: false, wait: true,
    parameters: [
      string(name: "DEVICE_TAG", value: "$device"),
      booleanParam(name: "BOOT", value: false),
      booleanParam(name: "TURN_OFF", value: true),
      booleanParam(name: "RELOAD_ONLY", value: false),
    ],
  )
  if (job.result != "SUCCESS") {
    unstable("FAILED: ${device}")
    currentBuild.result = "FAILURE"
  }
}

pipeline {
  agent { label 'built-in' }
  triggers {
    cron('0 19 * * *')
  }
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
    stage('Poweroff') {
      steps {
        script {
          def devices = ['lenovo-x1', 'orin-agx', 'orin-agx-64', 'orin-nx']
          devices.each { device ->
            stage("${device}") {
              script {
                poweroff(device)
              }
            }
          }
        }
      }
    }
  }
}