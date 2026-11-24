// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
[
  [tag: null, url: '', expected: 'Missing OCI_TAG'],
  [tag: '', url: '', expected: 'Missing OCI_TAG'],
  [tag: '   ', url: '', expected: 'Missing OCI_TAG'],
  [tag: 'release-test', url: '', expected: 'ARTIFACTS_URL parameter is required'],
  [tag: 'release-test', url: 'invalid', expected: 'Unexpected ARTIFACTS_URL'],
  [tag: 'release-test', url: 'https://ci/artifacts/20261124_123456789-commit_' + ('a' * 40), expected: null],
].each { example ->
  def commands = []
  def environment = [JENKINS_RELEASE_CANDIDATE_JOB: 'ghaf-release-candidate']
  def pipeline = new GroovyShell(new Binding([
    params: [GHAF_VERSION: 'ghaf-test', OCI_TAG: example.tag, ARTIFACTS_URL: example.url],
    env: environment,
    properties: { args -> }, parameters: { args -> args }, string: { args -> args },
    pipeline: { body -> body() }, agent: { body -> }, options: { body -> },
    stages: { body -> body() }, steps: { body -> body() }, script: { body -> body() },
    stage: { name, body -> if (name in ['Setup', 'Check artifacts']) body() },
    dir: { name, body -> body() },
    sh: { command -> commands << command.toString() },
    error: { message -> throw new IllegalArgumentException(message.toString()) },
  ])).parse(new File(repoRoot, 'modules/jenkins/pipelines/ghaf-release-publish.groovy'))
  try {
    pipeline.run()
    assert example.expected == null : 'Setup accepted an invalid release configuration'
    assert environment.OCI_TAG == example.tag
    assert environment.ARTIFACTS_DIR.endsWith('20261124_123456789-commit_' + ('a' * 40) + '/')
    assert commands.size() == 1
  } catch (IllegalArgumentException error) {
    assert example.expected != null && error.message.contains(example.expected)
    assert commands.isEmpty() : 'Invalid setup must fail before any shell commands or Cachix operations'
  }
}
