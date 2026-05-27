// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
def pipelineModel = new GroovyShell().parse(
  new File(repoRoot, 'hosts/hetzci/pipeline-library/vars/pipelineModel.groovy')
)

def expectFailure(String messagePart, Closure body) {
  try {
    body()
    assert false : "Expected failure containing '${messagePart}'"
  } catch (IllegalArgumentException e) {
    assert e.message.contains(messagePart) : "Unexpected message: ${e.message}"
  }
}

assert pipelineModel.short_target_name('packages.x86_64-linux.lenovo-x1-carbon-gen11-debug') ==
  'lenovo-x1-carbon-gen11-debug'
assert pipelineModel.short_target_name('plain-target') == 'plain-target'
assert pipelineModel.safe_path_component('ghaf/main 1@prod') == 'ghaf-main-1-prod'
assert pipelineModel.safe_stage_key(
  'x86_64-linux.lenovo@_relayboot bat_@prod@no-secureboot'
) == 'x86_64-linux.lenovo___relayboot-bat___prod__no-secureboot'
assert pipelineModel.html_escape(null) == null
assert pipelineModel.html_escape('<script data-x="a&b">\'</script>') ==
  '&lt;script data-x=&quot;a&amp;b&quot;&gt;&#39;&lt;/script&gt;'
assert pipelineModel.display_testset('_relayboot_bat_') == 'relayboot bat'

def sampleTestTarget = 'packages.x86_64-linux.lenovo-x1-carbon-gen11-debug'
def sampleTestIdentityTarget = 'x86_64-linux.lenovo-x1-carbon-gen11-debug'
assert pipelineModel.test_identity([
  target: sampleTestTarget,
  testset: '_relayboot_bat_',
  effective_testagent_host: 'prod',
]) == "${sampleTestIdentityTarget}@_relayboot_bat_@prod@no-secureboot"
assert pipelineModel.test_identity([
  target: sampleTestTarget,
  testset: '_relayboot_bat_',
], true) == "${sampleTestIdentityTarget}@_relayboot_bat_@any@secureboot"

def normalizedLegacyBuild = pipelineModel.normalize_build_config([
  target: sampleTestTarget,
  testset: '_relayboot_bat_',
  test_secboot: true,
  uefisign: true,
  build_otapin: true,
  sbom: true,
], true, 'prod', 'prod')

assert normalizedLegacyBuild.target == sampleTestTarget
assert normalizedLegacyBuild.shortname == 'lenovo-x1-carbon-gen11-debug'
assert normalizedLegacyBuild.no_image == false
assert normalizedLegacyBuild.uefi_sign_requested == true
assert normalizedLegacyBuild.has_testset == true
assert normalizedLegacyBuild.test_secboot_requested == true
assert normalizedLegacyBuild.provenance_requested == true
assert normalizedLegacyBuild.build_otapin_requested == true
assert normalizedLegacyBuild.sbom_requested == true
assert normalizedLegacyBuild.can_uefi_sign == true
assert normalizedLegacyBuild.run_secboot_test == true
assert normalizedLegacyBuild.tests.size() == 1
assert normalizedLegacyBuild.tests[0].target == sampleTestTarget
assert normalizedLegacyBuild.tests[0].shortname == 'lenovo-x1-carbon-gen11-debug'
assert normalizedLegacyBuild.tests[0].testagent_host_override == null
assert normalizedLegacyBuild.tests[0].effective_testagent_host == 'prod'
assert normalizedLegacyBuild.tests[0].secureboot_requested == true
assert normalizedLegacyBuild.tests[0].id ==
  "${sampleTestIdentityTarget}@_relayboot_bat_@prod@no-secureboot"
assert normalizedLegacyBuild.tests[0].secureboot_id ==
  "${sampleTestIdentityTarget}@_relayboot_bat_@prod@secureboot"
assert normalizedLegacyBuild.test_runs*.stage_name == [
  'Test lenovo-x1-carbon-gen11-debug / relayboot bat / prod / no-secureboot',
  'Test lenovo-x1-carbon-gen11-debug / relayboot bat / prod / secureboot',
]

def normalizedDocBuild = pipelineModel.normalize_build_config([
  target: 'packages.x86_64-linux.doc',
  no_image: true,
  testset: null,
  provenance: false,
], true, 'prod', 'prod')

assert normalizedDocBuild.shortname == 'doc'
assert normalizedDocBuild.no_image == true
assert normalizedDocBuild.has_testset == false
assert normalizedDocBuild.provenance_requested == false
assert normalizedDocBuild.can_uefi_sign == false
assert normalizedDocBuild.run_secboot_test == false
assert normalizedDocBuild.tests.isEmpty()

def normalizedVmBuild = pipelineModel.normalize_build_config([
  target: 'packages.x86_64-linux.system76-darp11-b-debug',
  testset: '_relayboot_bat_',
  test_secboot: true,
  uefisign: true,
], false, 'vm', 'prod')

assert normalizedVmBuild.uefi_sign_requested == true
assert normalizedVmBuild.can_uefi_sign == false
assert normalizedVmBuild.run_secboot_test == false

def normalizedExplicitTests = pipelineModel.normalize_tests([
  target: 'packages.x86_64-linux.intel-laptop-debug',
  tests: [
    [
      target: 'packages.x86_64-linux.lenovo-x1-carbon-gen11-debug',
      testset: '_relayboot_bat_',
      test_secboot: true,
    ],
    [
      target: 'packages.x86_64-linux.system76-darp11-b-debug',
      testset: '_relayboot_bat_',
      testagent_host: 'release',
    ],
  ],
], 'prod')

assert normalizedExplicitTests.size() == 2
assert normalizedExplicitTests[0].effective_testagent_host == 'prod'
assert normalizedExplicitTests[0].secureboot_requested == true
assert normalizedExplicitTests[0].test_path_key ==
  'x86_64-linux.lenovo-x1-carbon-gen11-debug___relayboot_bat___prod__no-secureboot'
assert normalizedExplicitTests[1].testagent_host_override == 'release'
assert normalizedExplicitTests[1].effective_testagent_host == 'release'
assert normalizedExplicitTests[1].id ==
  'x86_64-linux.system76-darp11-b-debug@_relayboot_bat_@release@no-secureboot'

def normalizedBuildWithExplicitTests = pipelineModel.normalize_build_config([
  target: 'packages.x86_64-linux.intel-laptop-debug',
  tests: [
    [
      target: 'packages.x86_64-linux.lenovo-x1-carbon-gen11-debug',
      testset: '_relayboot_bat_',
      test_secboot: true,
    ],
    [
      target: 'packages.x86_64-linux.system76-darp11-b-debug',
      testset: '_relayboot_bat_',
      testagent_host: 'release',
    ],
  ],
], true, 'prod', 'prod')

assert normalizedBuildWithExplicitTests.tests.size() == 2
assert normalizedBuildWithExplicitTests.has_testset == false
assert normalizedBuildWithExplicitTests.tests[1].effective_testagent_host == 'release'
assert normalizedBuildWithExplicitTests.test_runs.size() == 3
assert normalizedBuildWithExplicitTests.test_runs*.stage_name == [
  'Test lenovo-x1-carbon-gen11-debug / relayboot bat / prod / no-secureboot',
  'Test lenovo-x1-carbon-gen11-debug / relayboot bat / prod / secureboot',
  'Test system76-darp11-b-debug / relayboot bat / release / no-secureboot',
]
assert normalizedBuildWithExplicitTests.test_runs[1].initial_status == 'SKIPPED'
assert normalizedBuildWithExplicitTests.test_runs[1].initial_reason == 'secureboot_not_available'

def skippedTestEntry = pipelineModel.test_result_entry(normalizedBuildWithExplicitTests.test_runs[1])
assert skippedTestEntry.status == 'SKIPPED'
assert skippedTestEntry.reason == 'secureboot_not_available'
assert skippedTestEntry.artifacts ==
  'test-results/x86_64-linux.lenovo-x1-carbon-gen11-debug___relayboot_bat___prod__secureboot'

def finishedTestEntry = pipelineModel.test_result_entry(
  normalizedBuildWithExplicitTests.test_runs[0],
  [
    status: 'SUCCESS',
    job: [
      url: 'https://ci.example.invalid/job/ghaf-hw-test/42/',
      number: 42,
      result: 'SUCCESS',
    ],
  ]
)
assert finishedTestEntry.status == 'SUCCESS'
assert finishedTestEntry.job == [
  url: 'https://ci.example.invalid/job/ghaf-hw-test/42/',
  number: 42,
  result: 'SUCCESS',
]

expectFailure('Missing target name') {
  pipelineModel.normalize_build_config([:], true, 'prod', 'prod')
}

expectFailure("Explicit 'tests' entries are not supported by create_pipeline() yet") {
  pipelineModel.normalize_build_config([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    tests: [[
      target: sampleTestTarget,
      testset: '_relayboot_bat_',
    ]],
  ], true, 'prod', 'prod', false)
}

expectFailure("use either 'tests' or legacy 'testset'") {
  pipelineModel.normalize_tests([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    testset: '_relayboot_bat_',
    tests: [[
      target: sampleTestTarget,
      testset: '_relayboot_bat_',
    ]],
  ], 'prod')
}

expectFailure('expected a list') {
  pipelineModel.normalize_tests([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    tests: [
      target: sampleTestTarget,
      testset: '_relayboot_bat_',
    ],
  ], 'prod')
}

expectFailure('no_image builds cannot define tests') {
  pipelineModel.normalize_tests([
    target: 'packages.x86_64-linux.doc',
    no_image: true,
    tests: [[
      target: sampleTestTarget,
      testset: '_relayboot_bat_',
    ]],
  ], 'prod')
}

expectFailure('Duplicate canonical test identity') {
  pipelineModel.normalize_tests([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    tests: [
      [
        target: sampleTestTarget,
        testset: '_relayboot_bat_',
      ],
      [
        target: sampleTestTarget,
        testset: '_relayboot_bat_',
      ],
    ],
  ], 'prod')
}

expectFailure('Duplicate test path key') {
  pipelineModel.normalize_tests([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    tests: [
      [
        target: sampleTestTarget,
        testset: 'collision/a',
      ],
      [
        target: sampleTestTarget,
        testset: 'collision?a',
      ],
    ],
  ], 'prod')
}

expectFailure('Duplicate test stage name') {
  pipelineModel.normalize_build_config([
    target: 'packages.x86_64-linux.intel-laptop-debug',
    tests: [
      [
        target: 'packages.x86_64-linux.same-shortname',
        testset: '_relayboot_',
      ],
      [
        target: 'packages.aarch64-linux.same-shortname',
        testset: '_relayboot_',
      ],
    ],
  ], true, 'prod', null)
}

expectFailure("reserved in canonical test identities") {
  pipelineModel.test_identity([
    target: sampleTestTarget,
    testset: 'bad@testset',
    effective_testagent_host: 'prod',
  ])
}

println 'PipelineModelTest passed'
