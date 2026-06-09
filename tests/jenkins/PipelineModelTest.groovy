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

def sampleTestset = '_relayboot_bat_'
def sampleTestTarget = 'packages.x86_64-linux.lenovo-x1-carbon-gen11-debug'
def sampleTestShortTarget = 'lenovo-x1-carbon-gen11-debug'
def sampleTestIdentityTarget = 'x86_64-linux.lenovo-x1-carbon-gen11-debug'
def sampleStoreDiskInstallerTarget = 'system76-darp11-b-storeDisk-debug-installer'
def explicitTestsBuildTarget = 'packages.x86_64-linux.intel-laptop-debug'
def explicitTests = [
  [
    test_target: sampleTestShortTarget,
    testset: sampleTestset,
    test_secboot: true,
  ],
  [
    test_target: 'system76-darp11-b-debug',
    testset: sampleTestset,
    testagent_host: 'release',
  ],
]
def explicitTestsConfig = [target: explicitTestsBuildTarget, tests: explicitTests]
def withExplicitTestsTarget = { config -> [target: explicitTestsBuildTarget] + config }

assert pipelineModel.short_target_name(sampleTestTarget) == sampleTestShortTarget
assert pipelineModel.safe_path_component('ghaf/main 1@prod') == 'ghaf-main-1-prod'
assert pipelineModel.safe_stage_key(
  'x86_64-linux.lenovo@_relayboot bat_@prod@no-secureboot'
) == 'x86_64-linux.lenovo___relayboot-bat___prod__no-secureboot'
assert pipelineModel.html_escape('<script data-x="a&b">\'</script>') ==
  '&lt;script data-x=&quot;a&amp;b&quot;&gt;&#39;&lt;/script&gt;'
assert pipelineModel.test_identity([
  target: sampleTestTarget,
  testset: sampleTestset,
  effective_testagent_host: 'prod',
]) == "${sampleTestIdentityTarget}@${sampleTestset}@prod@no-secureboot"
assert pipelineModel.test_identity([
  target: sampleTestTarget,
  testset: sampleTestset,
], true) == "${sampleTestIdentityTarget}@${sampleTestset}@any@secureboot"
assert pipelineModel.device_info(sampleTestShortTarget, false) == [name: 'LenovoX1-1', tag: 'lenovo-x1']
assert pipelineModel.device_info(sampleTestShortTarget, true) == [name: 'X1-Secure-Boot', tag: 'x1-sec-boot']
assert pipelineModel.device_info(sampleTestShortTarget, true, 'lenovo-x1') ==
  [name: 'X1-Secure-Boot', tag: 'x1-sec-boot']
assert pipelineModel.device_info(sampleTestShortTarget, false, 'x1-sec-boot') ==
  [name: 'X1-Secure-Boot', tag: 'x1-sec-boot']
assert pipelineModel.device_info(sampleTestShortTarget, false, 'darter-pro') == null
assert pipelineModel.device_info('system76-darp11-b-debug', true, 'lenovo-x1') == null

def normalizedLegacyBuild = pipelineModel.normalize_build_config([
  target: sampleTestTarget,
  testset: sampleTestset,
  test_secboot: true,
  uefisign: true,
  build_otapin: true,
  sbom: true,
], true, 'prod', 'prod')

assert normalizedLegacyBuild.tests[0].effective_testagent_host == 'prod'
assert normalizedLegacyBuild.tests[0].id ==
  "${sampleTestIdentityTarget}@${sampleTestset}@prod@no-secureboot"
assert normalizedLegacyBuild.tests[0].secureboot_id ==
  "${sampleTestIdentityTarget}@${sampleTestset}@prod@secureboot"
assert normalizedLegacyBuild.test_runs*.stage_name == [
  'lenovo-x1 / relayboot bat / no-secureboot',
  'lenovo-x1 / relayboot bat / secureboot',
]

def normalizedDocBuild = pipelineModel.normalize_build_config([
  target: 'packages.x86_64-linux.doc',
  no_image: true,
  testset: null,
  provenance: false,
], true, 'prod', 'prod')

assert normalizedDocBuild.tests.isEmpty()

def normalizedVmBuild = pipelineModel.normalize_build_config([
  target: 'packages.x86_64-linux.system76-darp11-b-debug',
  testset: sampleTestset,
  test_secboot: true,
  uefisign: true,
], false, 'vm', 'prod')

assert normalizedVmBuild.test_runs*.initial_reason == ['ci_env_vm', 'ci_env_vm']

def normalizedExplicitTests = pipelineModel.normalize_tests(explicitTestsConfig, 'prod')

assert normalizedExplicitTests[0].test_path_key ==
  'lenovo-x1-carbon-gen11-debug___relayboot_bat___prod__no-secureboot'
assert normalizedExplicitTests[0].device_tag == 'lenovo-x1'
assert normalizedExplicitTests[1].effective_testagent_host == 'release'
assert normalizedExplicitTests[1].id ==
  'system76-darp11-b-debug@_relayboot_bat_@release@no-secureboot'

def normalizedDeviceTagTests = pipelineModel.normalize_tests([
  target: 'packages.x86_64-linux.intel-laptop-storeDisk-debug-installer',
  tests: [[
    device_tag: 'darter-pro',
    variant: 'storeDisk-debug-installer',
    testset: sampleTestset,
  ]],
], 'prod')

assert normalizedDeviceTagTests[0].device_tag == 'darter-pro'
assert normalizedDeviceTagTests[0].target == sampleStoreDiskInstallerTarget
assert normalizedDeviceTagTests[0].test_path_key ==
  'system76-darp11-b-storeDisk-debug-installer___relayboot_bat___prod__no-secureboot'

def normalizedBuildWithExplicitTests = pipelineModel.normalize_build_config(explicitTestsConfig, true, 'prod', 'prod')

assert normalizedBuildWithExplicitTests.test_runs*.stage_name == [
  'lenovo-x1 / relayboot bat / no-secureboot',
  'lenovo-x1 / relayboot bat / secureboot',
  'darter-pro / relayboot bat / release / no-secureboot',
]
assert normalizedBuildWithExplicitTests.test_runs[1].initial_status == 'SKIPPED'
assert normalizedBuildWithExplicitTests.test_runs[1].initial_reason == 'secureboot_not_available'

def normalizedInferredDeviceBuild = pipelineModel.normalize_build_config([
  target: 'packages.aarch64-linux.nvidia-jetson-orin-agx-debug',
  testset: sampleTestset,
], true, 'prod', null)

assert normalizedInferredDeviceBuild.test_runs*.stage_name == [
  'orin-agx / relayboot bat / no-secureboot',
]

def normalizedAnyOverrideBuild = pipelineModel.normalize_build_config([
  target: explicitTestsBuildTarget,
  tests: [
    [
      test_target: sampleTestShortTarget,
      testset: sampleTestset,
    ],
    [
      test_target: sampleTestShortTarget,
      testset: sampleTestset,
      testagent_host: 'any',
    ],
  ],
], true, 'prod', 'prod')

assert normalizedAnyOverrideBuild.test_runs*.stage_name == [
  'lenovo-x1 / relayboot bat / no-secureboot',
  'lenovo-x1 / relayboot bat / any / no-secureboot',
]

def normalizedFallbackDisplayBuild = pipelineModel.normalize_build_config([
  target: explicitTestsBuildTarget,
  tests: [
    [
      device_tag: 'lenovo-x1',
      variant: 'debug',
      testset: sampleTestset,
    ],
    [
      device_tag: 'lenovo-x1',
      variant: 'debug-installer',
      testset: sampleTestset,
    ],
  ],
], true, 'prod', null)

assert normalizedFallbackDisplayBuild.test_runs*.stage_name == [
  'lenovo-x1-carbon-gen11-debug / relayboot bat / no-secureboot',
  'lenovo-x1-carbon-gen11-debug-installer / relayboot bat / no-secureboot',
]

def skippedTestEntry = pipelineModel.test_result_entry(normalizedBuildWithExplicitTests.test_runs[1])
assert skippedTestEntry.status == 'SKIPPED'
assert skippedTestEntry.reason == 'secureboot_not_available'
assert skippedTestEntry.artifacts ==
  'test-results/lenovo-x1-carbon-gen11-debug___relayboot_bat___prod__secureboot'

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

[
  [
    message: "use either 'tests' or legacy 'testset'",
    config: withExplicitTestsTarget([
      testset: sampleTestset,
      tests: [[
        test_target: sampleTestTarget,
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: 'expected a list',
    config: withExplicitTestsTarget([
      tests: [
        test_target: sampleTestTarget,
        testset: sampleTestset,
      ],
    ]),
  ],
  [
    message: 'no_image builds cannot define tests',
    config: [
      target: 'packages.x86_64-linux.doc',
      no_image: true,
      tests: [[
        test_target: sampleTestTarget,
        testset: sampleTestset,
      ]],
    ],
  ],
  [
    message: 'Duplicate canonical test identity',
    config: withExplicitTestsTarget([
      tests: [
        [
          test_target: sampleTestShortTarget,
          testset: sampleTestset,
        ],
        [
          test_target: sampleTestShortTarget,
          testset: sampleTestset,
        ],
      ],
    ]),
  ],
  [
    message: 'Duplicate test path key',
    config: withExplicitTestsTarget([
      tests: [
        [
          test_target: sampleTestShortTarget,
          testset: 'collision/a',
        ],
        [
          test_target: sampleTestShortTarget,
          testset: 'collision?a',
        ],
      ],
    ]),
  ],
  [
    message: "Unknown device_tag 'unknown-device'",
    config: withExplicitTestsTarget([
      tests: [[
        device_tag: 'unknown-device',
        variant: 'debug',
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: "device_tag 'x1-sec-boot' does not support variants",
    config: withExplicitTestsTarget([
      tests: [[
        device_tag: 'x1-sec-boot',
        variant: 'debug',
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: "'variant' requires 'device_tag'",
    config: withExplicitTestsTarget([
      tests: [[
        variant: 'debug',
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: "'device_tag' requires 'variant'",
    config: withExplicitTestsTarget([
      tests: [[
        device_tag: 'lenovo-x1',
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: "use either 'test_target' or 'device_tag'",
    config: withExplicitTestsTarget([
      tests: [[
        test_target: sampleTestShortTarget,
        device_tag: 'lenovo-x1',
        variant: 'debug',
        testset: sampleTestset,
      ]],
    ]),
  ],
  [
    message: "full 'packages.<system>.<target>' value or a short target name",
    config: withExplicitTestsTarget([
      tests: [[
        test_target: 'x86_64-linux.lenovo-x1-carbon-gen11-debug',
        testset: sampleTestset,
      ]],
    ]),
  ],
].each { failureCase ->
  expectFailure(failureCase.message) {
    pipelineModel.normalize_tests(failureCase.config, 'prod')
  }
}

expectFailure('Duplicate test stage name') {
  pipelineModel.normalize_build_config([
    target: explicitTestsBuildTarget,
    tests: [
      [
        test_target: 'same-shortname',
        testset: '_relayboot_',
      ],
      [
        test_target: 'packages.aarch64-linux.same-shortname',
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
