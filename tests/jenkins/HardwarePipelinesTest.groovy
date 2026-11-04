// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
def classLoader = new GroovyClassLoader()
classLoader.parseClass('@interface Library { String[] value() }')
def manual = new GroovyShell(classLoader, new Binding([
  booleanParam: { Map args -> args },
  string: { Map args -> args },
  choice: { Map args -> args },
])).parse(new File(repoRoot, 'modules/jenkins/pipelines/ghaf-hw-test-manual.groovy'))

def agentChoices = [devices: ['lenovo-x1', 'orin-nx'], hosts: ['dev', 'prod', 'release']]
[
  [defaults: [:], devices: ['', 'lenovo-x1', 'orin-nx'], hosts: ['', 'dev', 'prod', 'release']],
  [
    defaults: [DEVICE_TAG: 'orin-nx', TESTAGENT_HOST: 'prod'],
    devices: ['orin-nx', '', 'lenovo-x1'], hosts: ['prod', '', 'dev', 'release'],
  ],
  [
    defaults: [DEVICE_TAG: 'unknown', TESTAGENT_HOST: 'unknown'],
    devices: ['', 'lenovo-x1', 'orin-nx'], hosts: ['', 'dev', 'prod', 'release'],
  ],
].each { example ->
  def parameters = manual.pipelineParameters(false, example.defaults, agentChoices)
  assert parameters.find { it.name == 'DEVICE_TAG' }.choices == example.devices
  assert parameters.find { it.name == 'TESTAGENT_HOST' }.choices == example.hosts
}
def emptyParameters = manual.pipelineParameters(false, [:], [devices: [], hosts: []])
assert emptyParameters.find { it.name == 'DEVICE_TAG' }.choices == ['']
assert emptyParameters.find { it.name == 'TESTAGENT_HOST' }.choices == ['']

def inNode = false
def onlineNodes = []
def builds = []
def warnings = []
def env = [:]
def nightly = new GroovyShell(new Binding([
  env: env,
  node: { String label, Closure body ->
    assert label == 'built-in'
    inNode = true
    env.JENKINS_HW_TEST_MANUAL_JOB = 'custom-hw-test-manual'
    try {
      body()
    } finally {
      env.remove('JENKINS_HW_TEST_MANUAL_JOB')
      inNode = false
    }
  },
  nodesByLabel: { Map args ->
    assert inNode
    assert args.label == 'dev-lenovo-x1'
    assert !args.offline
    onlineNodes
  },
  string: { Map args -> args },
  booleanParam: { Map args -> args },
  unstable: { String message -> warnings << message },
  build: { Map args ->
    assert !inNode : 'The downstream wait must release the controller executor'
    assert args.job == 'custom-hw-test-manual'
    assert args.wait && !args.propagate
    assert args.parameters.find { it.name == 'DEVICE_TAG' }.value == 'lenovo-x1'
    assert args.parameters.find { it.name == 'TESTAGENT_HOST' }.value == 'dev'
    builds << args
    [result: 'SUCCESS']
  },
])).parse(new File(repoRoot, 'modules/jenkins/pipelines/ghaf-nightly-poweroff.groovy'))

nightly.poweroff('lenovo-x1')
assert builds.isEmpty()
assert warnings.size() == 1

onlineNodes = ['dev-lenovo-x1']
nightly.poweroff('lenovo-x1')
assert builds.size() == 1
assert warnings.size() == 1
