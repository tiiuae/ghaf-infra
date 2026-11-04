// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
def classLoader = new GroovyClassLoader()
classLoader.parseClass('@interface NonCPS {}')
def hwTestUtils = new GroovyShell(classLoader).parse(
  new File(repoRoot, 'modules/jenkins/pipeline-library/vars/hwTestUtils.groovy')
)

def agx64Target = 'nvidia-jetson-orin-agx64-debug'
assert hwTestUtils.extra_tag_suffix(agx64Target, 'orin-agx-64') == 'NOTsecboot-only'
assert hwTestUtils.extra_tag_suffix(agx64Target, 'agx-64-sec-boot') == 'NOTexcl-secboot'

def inNode = false
def env = [BUILD_URL: 'https://ci.example.invalid/job/build/1/', JOB_NAME: 'build', BUILD_ID: '1']
hwTestUtils.binding = new Binding([
  env: env,
  pipelineModel: new GroovyShell().parse(
    new File(repoRoot, 'modules/jenkins/pipeline-library/vars/pipelineModel.groovy')
  ),
  node: { String label, Closure body ->
    assert label == 'built-in'
    inNode = true
    env.JENKINS_HW_TEST_JOB = 'custom-hw-test'
    try {
      body()
    } finally {
      env.remove('JENKINS_HW_TEST_JOB')
      inNode = false
    }
  },
  string: { Map args -> args },
  booleanParam: { Map args -> args },
  build: { Map args ->
    assert !inNode : 'The downstream wait must release the controller executor'
    assert args.job == 'custom-hw-test'
    assert args.wait && !args.propagate
    assert args.parameters.find { it.name == 'OCI_IMAGE_REF' }.value == 'registry.example.invalid/image:tag'
    [absoluteUrl: 'https://ci.example.invalid/job/custom-hw-test/42/', number: 42, result: 'SUCCESS']
  },
])

def job = hwTestUtils.run_hw_test(
  'build', agx64Target, 'test-identity', '_relayboot_', 'dev',
  [primary: [reference: 'registry.example.invalid/image:tag']], false, 'dev'
)
assert job == [
  name: 'custom-hw-test',
  url: 'https://ci.example.invalid/job/custom-hw-test/42/',
  number: 42,
  result: 'SUCCESS',
]
