// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

def fail(String message) {
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

def test_stage_name(Map testRun) {
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

def normalize_optional_string(value) {
  if (!(value instanceof String)) {
    return null
  }
  def trimmed = value.trim()
  return trimmed.isEmpty() ? null : trimmed
}

def shallow_copy_map(Map source) {
  def copy = [:]
  source.each { key, value ->
    copy[key] = value
  }
  return copy
}

def validate_test_identity_component(String name, String value) {
  if (value != null && value.contains('@')) {
    fail("Invalid ${name} '${value}': '@' is reserved in canonical test identities")
  }
}

def test_identity(Map testConfig, boolean secureboot = false) {
  if (testConfig == null) {
    fail("Missing test config")
  }

  def testTarget = testConfig.target
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
      target: rawTarget,
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

    def testTarget = rawTest.target
    if (!(testTarget instanceof String) || testTarget.isEmpty()) {
      fail("Missing test target for '${rawTarget}' entry #${idx + 1}")
    }

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
    normalizedTest.target = testTarget
    normalizedTest.shortname = short_target_name(testTarget)
    normalizedTest.testset = testset
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

def expand_test_runs(Map buildConfig) {
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
  String defaultTestagentHost = null,
  boolean allowExplicitTests = true) {
  if (targetConfig == null) {
    fail("Missing target config")
  }

  def targetName = targetConfig.target
  def targetLabel = targetName ?: '<unknown>'
  if (!allowExplicitTests && targetConfig.containsKey('tests')) {
    fail(
      "Explicit 'tests' entries are not supported by create_pipeline() yet for '${targetLabel}'; " +
        "use legacy build-level 'testset' until build-to-many fan-out lands"
    )
  }
  def normalized = shallow_copy_map(targetConfig)
  normalized.target = targetName
  normalized.shortname = short_target_name(targetName)
  normalized.ci_env = ciEnv
  normalized.no_image = normalized.get('no_image', false)
  normalized.signing_possible = signingPossible
  normalized.uefi_sign_requested = normalized.get('uefisign', false) || normalized.get('uefisigniso', false)
  normalized.testset = normalized.get('testset', null)
  normalized.has_testset = normalized.testset != null && !normalized.testset.isEmpty()
  normalized.test_secboot_requested = normalized.get('test_secboot', false)
  normalized.provenance_requested = normalized.get('provenance', true)
  normalized.build_otapin_requested = normalized.get('build_otapin', false)
  normalized.sbom_requested = normalized.get('sbom', false)
  normalized.can_uefi_sign = !normalized.no_image && signingPossible && normalized.uefi_sign_requested
  normalized.secureboot_execution_allowed = normalized.can_uefi_sign && ciEnv == "prod"
  normalized.tests = normalize_tests(normalized, defaultTestagentHost)
  normalized.test_runs = expand_test_runs(normalized)
  normalized.run_secboot_test =
    normalized.test_secboot_requested && normalized.secureboot_execution_allowed
  return normalized
}
