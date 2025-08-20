#!/usr/bin/env groovy

import groovy.transform.Field
@Field def MODULES = [:]

def REPO_URL = 'https://github.com/tiiuae/ghaf/'
def WORKDIR  = 'checkout'
def PIPELINE = [:]

properties([
  githubProjectProperty(displayName: '', projectUrlStr: REPO_URL),
  parameters([
    string(name: 'GITREF', defaultValue: 'main', description: 'Ghaf git reference (Commit/Branch/Tag)'),
    string(name: 'TESTSET', defaultValue: null, description: 'By default tests are skipped. To run hw-tests, define the target testset here; e.g.: _relayboot_, _relayboot_bat_, _relayboot_pre-merge_, etc.)'),
    booleanParam(name: 'doc', defaultValue: true, description: 'Build target packages.x86_64-linux.doc'),
    booleanParam(name: 'lenovo_x1_carbon_gen11_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.lenovo-x1-carbon-gen11-debug'),
    booleanParam(name: 'dell_latitude_7230_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7230-debug'),
    booleanParam(name: 'dell_latitude_7330_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.dell-latitude-7330-debug'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug_from_x86_64', defaultValue: false, description: 'Build target packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64'),
    booleanParam(name: 'nvidia_jetson_orin_agx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-agx-debug'),
    booleanParam(name: 'nvidia_jetson_orin_nx_debug', defaultValue: false, description: 'Build target packages.aarch64-linux.nvidia-jetson-orin-nx-debug'),
    booleanParam(name: 'system76_darp11_b_debug', defaultValue: false, description: 'Build target packages.x86_64-linux.system76-darp11-b-debug')
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
    stage('Setup') {
      steps {
        dir(WORKDIR) {
          script {
            def TARGETS = []
            if (params.doc) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.doc", testset: null ])
            }
            if (params.lenovo_x1_carbon_gen11_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.lenovo-x1-carbon-gen11-debug", testset: params.TESTSET ])
            }
            if (params.dell_latitude_7230_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7230-debug", testset: null ])
            }
            if (params.dell_latitude_7330_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.dell-latitude-7330-debug", testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_agx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64", testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_nx_debug_from_x86_64) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64", testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_agx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-agx-debug", testset: params.TESTSET ])
            }
            if (params.nvidia_jetson_orin_nx_debug) {
              TARGETS.push(
                [ target: "packages.aarch64-linux.nvidia-jetson-orin-nx-debug", testset: params.TESTSET ])
            }
            if (params.system76_darp11_b_debug) {
              TARGETS.push(
                [ target: "packages.x86_64-linux.system76-darp11-b-debug", testset: null ])
            }
            MODULES.utils = load "/etc/jenkins/pipelines/modules/utils.groovy"
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
}
