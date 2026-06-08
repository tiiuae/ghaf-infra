// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

private def fail(String message) {
  throw new IllegalArgumentException(message)
}

def short_target_name(String targetName) {
  if (!(targetName instanceof String) || targetName.isEmpty()) {
    fail("Missing target name")
  }
  def idx = targetName.lastIndexOf('.')
  return idx >= 0 ? targetName.substring(idx + 1) : targetName
}

def safe_path_component(String value) {
  if (value == null) {
    return null
  }
  return value.replaceAll(/[^A-Za-z0-9_.-]/, '-')
}

def safe_stage_key(String value) {
  if (value == null) {
    return null
  }
  return value.replace('@', '__').replaceAll(/[^A-Za-z0-9_.-]/, '-')
}

def html_escape(String value) {
  if (value == null) {
    return null
  }
  return value
    .replace('&', '&amp;')
    .replace('<', '&lt;')
    .replace('>', '&gt;')
    .replace('"', '&quot;')
    .replace("'", '&#39;')
}

def display_testset(String value) {
  def normalized = normalize_optional_string(value)
  if (normalized == null) {
    return null
  }
  normalized = normalized.replaceAll(/^_+|_+$/, '').replace('_', ' ')
  return normalized ?: value
}

private def device_catalog() {
  return [
    'orin-agx-64': [
      name: 'OrinAGX64',
      target_substrings: ['nvidia-jetson-orin-agx64'],
    ],
    'orin-agx': [
      name: 'OrinAGX1',
      target_substrings: ['nvidia-jetson-orin-agx'],
    ],
    'orin-nx': [
      name: 'OrinNX1',
      target_substrings: ['nvidia-jetson-orin-nx'],
    ],
    'lenovo-x1': [
      name: 'LenovoX1-1',
      target_substrings: ['lenovo-x1'],
      variants: [
        'debug': 'lenovo-x1-carbon-gen11-debug',
        'debug-installer': 'lenovo-x1-carbon-gen11-debug-installer',
      ],
    ],
    'x1-sec-boot': [
      name: 'X1-Secure-Boot',
    ],
    'dell-7330': [
      name: 'Dell7330',
      target_substrings: ['dell-latitude-7330'],
      variants: [
        'debug': 'dell-latitude-7330-debug',
      ],
    ],
    'darter-pro': [
      name: 'DarterPRO',
      target_substrings: ['system76-darp11-b'],
      variants: [
        'debug': 'system76-darp11-b-debug',
        'storeDisk-debug': 'system76-darp11-b-storeDisk-debug',
        'storeDisk-debug-installer': 'system76-darp11-b-storeDisk-debug-installer',
      ],
    ],
  ]
}

private def test_stage_name(Map testRun) {
  if (testRun == null) {
    fail("Missing test run")
  }
  def shortname = normalize_optional_string(testRun.get('shortname', null))
  if (shortname == null) {
    shortname = short_target_name(testRun.target)
  }
  def testset = display_testset(testRun.testset)
  def host = normalize_optional_string(testRun.get('effective_testagent_host', null)) ?: 'any'
  def mode = testRun.get('secureboot', false) ? 'secureboot' : 'no-secureboot'
  return "Test ${shortname} / ${testset} / ${host} / ${mode}".toString()
}

private def normalize_optional_string(value) {
  if (!(value instanceof String)) {
    return null
  }
  def trimmed = value.trim()
  return trimmed.isEmpty() ? null : trimmed
}

private def shallow_copy_map(Map source) {
  def copy = [:]
  source.each { key, value ->
    copy[key] = value
  }
  return copy
}

private def validate_test_identity_component(String name, String value) {
  if (value != null && value.contains('@')) {
    fail("Invalid ${name} '${value}': '@' is reserved in canonical test identities")
  }
}

def test_target_variants(String deviceTag) {
  def variants = device_catalog().get(normalize_optional_string(deviceTag), null)?.variants
  if (!(variants instanceof Map)) {
    return [:]
  }
  return variants
}

def test_target_for_variant(String deviceTag, String variant) {
  def resolvedTarget = test_target_variants(deviceTag).get(normalize_optional_string(variant), null)
  return resolvedTarget instanceof String ? resolvedTarget : null
}

def device_tag_for_target(String targetName) {
  def normalizedTarget = normalize_optional_string(targetName)
  if (normalizedTarget == null) {
    return null
  }

  def shortTarget = short_target_name(normalizedTarget)
  return device_catalog().findResult { String deviceTag, Map device ->
    def variants = device.variants
    if (variants instanceof Map && variants.values().contains(shortTarget)) {
      return deviceTag
    }
    return null
  }
}

def device_info(String targetName, boolean secureboot, String explicitDeviceTag = null) {
  def normalizedTarget = normalize_optional_string(targetName) ?: ''
  def normalizedDeviceTag = normalize_optional_string(explicitDeviceTag)

  if (normalizedDeviceTag != null) {
    if (normalizedDeviceTag == 'lenovo-x1' && secureboot && !normalizedTarget.contains('installer')) {
      return device_info_for_tag('x1-sec-boot')
    }
    return device_info_for_tag(normalizedDeviceTag)
  }

  if (normalizedTarget.contains('lenovo-x1') && secureboot && !normalizedTarget.contains('installer')) {
    return device_info_for_tag('x1-sec-boot')
  }

  return device_catalog().findResult { String deviceTag, Map device ->
    def targetSubstrings = device.target_substrings
    if (targetSubstrings instanceof List && targetSubstrings.any { normalizedTarget.contains(it as String) }) {
      return [name: device.name as String, tag: deviceTag]
    }
    return null
  }
}

private def device_info_for_tag(String deviceTag) {
  def device = device_catalog().get(deviceTag, null)
  if (!(device instanceof Map)) {
    return null
  }
  return [name: device.name as String, tag: deviceTag]
}

private def resolve_catalog_test_target(String deviceTag, String variant, String buildTarget, int idx) {
  def variants = test_target_variants(deviceTag)
  if (variants.isEmpty()) {
    fail("Unknown device_tag '${deviceTag}' for '${buildTarget}' entry #${idx + 1}")
  }

  def resolvedTarget = normalize_optional_string(test_target_for_variant(deviceTag, variant))
  if (!(resolvedTarget instanceof String) || resolvedTarget.isEmpty()) {
    def supportedVariants = variants.keySet().toList().sort().join(', ')
    fail(
      "Unknown variant '${variant}' for device_tag '${deviceTag}' in '${buildTarget}' entry #${idx + 1}; " +
        "supported variants: ${supportedVariants}"
    )
  }

  return [
    target: resolvedTarget,
    deviceTag: deviceTag,
  ]
}

private def resolve_explicit_test_target(Map testConfig, String buildTarget, int idx) {
  if (testConfig == null) {
    fail("Missing test config")
  }

  def explicitTestTarget = normalize_optional_string(testConfig.get('test_target', null))
  def explicitDeviceTag = normalize_optional_string(testConfig.get('device_tag', null))
  def explicitVariant = normalize_optional_string(testConfig.get('variant', null))

  if (explicitTestTarget != null) {
    if (explicitDeviceTag != null || explicitVariant != null) {
      fail(
        "Invalid test config for '${buildTarget}' entry #${idx + 1}: " +
          "use either 'test_target' or 'device_tag' + 'variant', not both"
      )
    }

    if (explicitTestTarget.contains('.') && !explicitTestTarget.startsWith('packages.')) {
      fail(
        "Invalid explicit test_target '${explicitTestTarget}': " +
          "use either a full 'packages.<system>.<target>' value or a short target name"
      )
    }

    return [
      target: explicitTestTarget,
      deviceTag: device_tag_for_target(explicitTestTarget),
    ]
  }

  if (explicitDeviceTag == null && explicitVariant == null) {
    fail("Missing test_target or device_tag for '${buildTarget}' entry #${idx + 1}")
  }

  if (explicitDeviceTag == null) {
    fail(
      "Missing device_tag for '${buildTarget}' entry #${idx + 1}: " +
        "'variant' requires 'device_tag'"
    )
  }

  if (explicitVariant == null) {
    fail(
      "Missing variant for '${buildTarget}' entry #${idx + 1}: " +
        "'device_tag' requires 'variant'"
    )
  }

  return resolve_catalog_test_target(explicitDeviceTag, explicitVariant, buildTarget, idx)
}

def test_identity(Map testConfig, boolean secureboot = false) {
  if (testConfig == null) {
    fail("Missing test config")
  }

  def testTarget = normalize_optional_string(testConfig.get('target', null))
  if (!(testTarget instanceof String) || testTarget.isEmpty()) {
    fail("Missing test target")
  }

  def testset = testConfig.testset
  if (!(testset instanceof String) || testset.isEmpty()) {
    fail("Missing testset for '${testTarget}'")
  }

  def effectiveHost = normalize_optional_string(testConfig.get('effective_testagent_host', null))
  if (effectiveHost == null) {
    effectiveHost = normalize_optional_string(testConfig.get('testagent_host_override', null))
  }
  if (effectiveHost == null) {
    effectiveHost = normalize_optional_string(testConfig.get('testagent_host', null))
  }

  validate_test_identity_component('test target', testTarget)
  validate_test_identity_component('testset', testset)
  validate_test_identity_component('testagent host', effectiveHost)

  def targetComponent = testTarget.replaceFirst(/^packages\./, '')
  def mode = secureboot ? 'secureboot' : 'no-secureboot'
  def hostComponent = effectiveHost == null ? 'any' : effectiveHost
  return "${targetComponent}@${testset}@${hostComponent}@${mode}".toString()
}

def test_result_entry(Map testRun, Map result = [:]) {
  if (testRun == null) {
    fail("Missing test run")
  }
  result = result ?: [:]

  def entry = [
    id: testRun.id,
    target: testRun.target,
    testset: testRun.testset,
    testagent_host_override: testRun.get('testagent_host_override', null),
    effective_testagent_host: testRun.get('effective_testagent_host', null),
    secureboot: testRun.get('secureboot', false),
    artifacts: testRun.get('artifacts', null) ?: "test-results/${testRun.test_path_key}",
  ]

  def status = result.containsKey('status') ? result.status : testRun.get('initial_status', null)
  def reason = result.containsKey('reason') ? result.reason : testRun.get('initial_reason', null)

  if (status != null) {
    entry.status = status
  }
  if (reason != null) {
    entry.reason = reason
  }
  if (result.get('job', null) instanceof Map) {
    entry.job = shallow_copy_map(result.job)
  }

  return entry
}

def normalize_tests(Map buildConfig, String defaultTestagentHost = null) {
  if (buildConfig == null) {
    fail("Missing build config")
  }

  def rawTarget = buildConfig.target
  if (!(rawTarget instanceof String) || rawTarget.isEmpty()) {
    fail("Missing target name")
  }

  def rawTests = []
  def legacyTestset = normalize_optional_string(buildConfig.get('testset', null))
  def hasLegacyTestset = legacyTestset != null

  if (buildConfig.containsKey('tests')) {
    def explicitTests = buildConfig.tests
    if (!(explicitTests instanceof List)) {
      fail("Invalid tests for '${rawTarget}': expected a list")
    }
    if (hasLegacyTestset) {
      fail("Invalid test config for '${rawTarget}': use either 'tests' or legacy 'testset', not both")
    }
    rawTests = explicitTests
  } else if (hasLegacyTestset) {
    rawTests = [[
      test_target: rawTarget,
      testset: legacyTestset,
      test_secboot: buildConfig.get('test_secboot', false),
    ]]
  }

  if (buildConfig.get('no_image', false) && !rawTests.isEmpty()) {
    fail("Invalid test config for '${rawTarget}': no_image builds cannot define tests")
  }

  def normalizedTests = []
  rawTests.eachWithIndex { rawTest, idx ->
    if (!(rawTest instanceof Map)) {
      fail("Invalid test entry #${idx + 1} for '${rawTarget}': expected a map")
    }

    def resolvedTestTarget = resolve_explicit_test_target(rawTest, rawTarget, idx)
    def testTarget = resolvedTestTarget.target

    def testset = rawTest.testset
    if (!(testset instanceof String) || testset.isEmpty()) {
      fail("Missing testset for '${testTarget}'")
    }

    def overrideFromExplicitField = normalize_optional_string(rawTest.get('testagent_host_override', null))
    def overrideFromAlias = normalize_optional_string(rawTest.get('testagent_host', null))
    if (
      overrideFromExplicitField != null &&
      overrideFromAlias != null &&
      overrideFromExplicitField != overrideFromAlias
    ) {
      fail(
        "Conflicting testagent host overrides for '${testTarget}': " +
          "'${overrideFromExplicitField}' vs '${overrideFromAlias}'"
      )
    }

    def testagentHostOverride = overrideFromExplicitField ?: overrideFromAlias
    def effectiveTestagentHost = testagentHostOverride ?: normalize_optional_string(defaultTestagentHost)
    def securebootRequested = rawTest.get('test_secboot', false)
    def identity = test_identity([
      target: testTarget,
      testset: testset,
      effective_testagent_host: effectiveTestagentHost,
    ])

    def normalizedTest = shallow_copy_map(rawTest)
    normalizedTest.remove('test_target')
    normalizedTest.remove('device_tag')
    normalizedTest.remove('variant')
    normalizedTest.target = testTarget
    normalizedTest.shortname = short_target_name(testTarget)
    normalizedTest.testset = testset
    normalizedTest.device_tag = resolvedTestTarget.deviceTag
    normalizedTest.testagent_host_override = testagentHostOverride
    normalizedTest.effective_testagent_host = effectiveTestagentHost
    normalizedTest.secureboot_requested = securebootRequested
    normalizedTest.id = identity
    normalizedTest.test_path_key = safe_stage_key(identity)
    if (securebootRequested) {
      def securebootIdentity = test_identity(normalizedTest, true)
      normalizedTest.secureboot_id = securebootIdentity
      normalizedTest.secureboot_test_path_key = safe_stage_key(securebootIdentity)
    }
    normalizedTests << normalizedTest
  }

  def seenIds = [:]
  def seenPathKeys = [:]
  normalizedTests.each { normalizedTest ->
    def runs = [
      [identity: normalizedTest.id, pathKey: normalizedTest.test_path_key],
    ]
    if (normalizedTest.secureboot_requested) {
      runs << [
        identity: normalizedTest.secureboot_id,
        pathKey: normalizedTest.secureboot_test_path_key,
      ]
    }

    runs.each { run ->
      if (seenIds.containsKey(run.identity)) {
        fail("Duplicate canonical test identity '${run.identity}' for build '${rawTarget}'")
      }
      if (seenPathKeys.containsKey(run.pathKey)) {
        fail("Duplicate test path key '${run.pathKey}' for build '${rawTarget}'")
      }
      seenIds[run.identity] = true
      seenPathKeys[run.pathKey] = true
    }
  }

  return normalizedTests
}

private def expand_test_runs(Map buildConfig) {
  if (buildConfig == null) {
    fail("Missing build config")
  }

  def buildTarget = buildConfig.target
  if (!(buildTarget instanceof String) || buildTarget.isEmpty()) {
    fail("Missing target name")
  }

  def normalizedTests = buildConfig.get('tests', [])
  if (!(normalizedTests instanceof List)) {
    fail("Invalid tests for '${buildTarget}': expected a list")
  }

  def ciEnv = normalize_optional_string(buildConfig.get('ci_env', null))
  def securebootExecutionAllowed = buildConfig.get('secureboot_execution_allowed', false)
  def runs = []

  normalizedTests.each { normalizedTest ->
    def normalRun = shallow_copy_map(normalizedTest)
    normalRun.id = normalizedTest.id
    normalRun.test_path_key = normalizedTest.test_path_key
    normalRun.secureboot = false
    normalRun.stage_name = test_stage_name(normalRun)
    normalRun.artifacts = "test-results/${normalRun.test_path_key}"
    if (ciEnv == 'vm') {
      normalRun.initial_status = 'SKIPPED'
      normalRun.initial_reason = 'ci_env_vm'
    }
    runs << normalRun

    if (normalizedTest.secureboot_requested) {
      def securebootRun = shallow_copy_map(normalizedTest)
      securebootRun.id = normalizedTest.secureboot_id
      securebootRun.test_path_key = normalizedTest.secureboot_test_path_key
      securebootRun.secureboot = true
      securebootRun.stage_name = test_stage_name(securebootRun)
      securebootRun.artifacts = "test-results/${securebootRun.test_path_key}"
      if (ciEnv == 'vm') {
        securebootRun.initial_status = 'SKIPPED'
        securebootRun.initial_reason = 'ci_env_vm'
      } else if (!securebootExecutionAllowed) {
        securebootRun.initial_status = 'SKIPPED'
        securebootRun.initial_reason = 'secureboot_not_available'
      }
      runs << securebootRun
    }
  }

  def seenStageNames = [:]
  runs.each { run ->
    if (seenStageNames.containsKey(run.stage_name)) {
      def previous = seenStageNames[run.stage_name]
      fail(
        "Duplicate test stage name '${run.stage_name}' for build '${buildTarget}': " +
          "'${previous.id}' and '${run.id}'"
      )
    }
    seenStageNames[run.stage_name] = run
  }

  return runs
}

def normalize_build_config(
  Map targetConfig,
  boolean signingPossible,
  String ciEnv,
  String defaultTestagentHost = null) {
  if (targetConfig == null) {
    fail("Missing target config")
  }

  def targetName = targetConfig.target
  def normalized = shallow_copy_map(targetConfig)
  normalized.target = targetName
  normalized.shortname = short_target_name(targetName)
  normalized.ci_env = ciEnv
  normalized.no_image = normalized.get('no_image', false)
  normalized.signing_possible = signingPossible
  normalized.uefi_sign_requested = normalized.get('uefisign', false) || normalized.get('uefisigniso', false)
  normalized.testset = normalized.get('testset', null)
  normalized.provenance_requested = normalized.get('provenance', true)
  normalized.build_otapin_requested = normalized.get('build_otapin', false)
  normalized.sbom_requested = normalized.get('sbom', false)
  normalized.can_uefi_sign = !normalized.no_image && signingPossible && normalized.uefi_sign_requested
  normalized.secureboot_execution_allowed = normalized.can_uefi_sign && ciEnv == "prod"
  normalized.tests = normalize_tests(normalized, defaultTestagentHost)
  normalized.test_runs = expand_test_runs(normalized)
  return normalized
}
