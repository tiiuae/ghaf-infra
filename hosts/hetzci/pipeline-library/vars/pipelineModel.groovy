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

private def display_device_tag(Map testRun) {
  if (testRun == null) {
    fail("Missing test run")
  }

  def explicitTag = normalize_optional_string(testRun.get('device_tag', null))
  if (explicitTag != null) {
    return explicitTag == 'x1-sec-boot' ? 'lenovo-x1' : explicitTag
  }

  def inferredInfo = device_info(testRun.target, testRun.get('secureboot', false))
  if (!(inferredInfo instanceof Map)) {
    return null
  }

  def inferredTag = normalize_optional_string(inferredInfo.get('tag', null))
  if (inferredTag == null) {
    return null
  }

  return inferredTag == 'x1-sec-boot' ? 'lenovo-x1' : inferredTag
}

private def target_stage_subject(Map testRun) {
  if (testRun == null) {
    fail("Missing test run")
  }

  def shortname = normalize_optional_string(testRun.get('shortname', null))
  if (shortname == null) {
    return short_target_name(testRun.target)
  }

  return shortname
}

private def test_stage_name(Map testRun, String subject) {
  if (testRun == null) {
    fail("Missing test run")
  }

  def testset = display_testset(testRun.testset)
  def mode = testRun.get('secureboot', false) ? 'secureboot' : 'no-secureboot'
  def components = [subject, testset]
  def host = normalize_optional_string(testRun.get('testagent_host_override', null))
  if (host != null) {
    components << host
  }
  components << mode
  return components.join(' / ').toString()
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

private def device_tag_for_target(String targetName) {
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

private def info_for_device_tag(String deviceTag) {
  def device = device_catalog().get(deviceTag, null)
  if (!(device instanceof Map)) {
    return null
  }
  return [name: device.name as String, tag: deviceTag]
}

private def inferred_device_info(String targetName, boolean secureboot) {
  def normalizedTarget = normalize_optional_string(targetName)
  if (normalizedTarget == null) {
    return null
  }

  if (normalizedTarget.contains('lenovo-x1') && secureboot && !normalizedTarget.contains('installer')) {
    return info_for_device_tag('x1-sec-boot')
  }

  return device_catalog().findResult { String deviceTag, Map device ->
    def targetSubstrings = device.target_substrings
    if (targetSubstrings instanceof List && targetSubstrings.any { normalizedTarget.contains(it as String) }) {
      return [name: device.name as String, tag: deviceTag]
    }
    return null
  }
}

def device_info(String targetName, boolean secureboot, String explicitDeviceTag = null) {
  def normalizedDeviceTag = normalize_optional_string(explicitDeviceTag)
  def inferredInfo = inferred_device_info(targetName, secureboot)

  if (normalizedDeviceTag != null) {
    def explicitInfo = info_for_device_tag(normalizedDeviceTag)
    if (explicitInfo == null) {
      return null
    }

    if (inferredInfo == null) {
      return explicitInfo
    }

    def explicitTag = normalizedDeviceTag
    if (explicitTag == 'lenovo-x1' && inferredInfo.tag == 'x1-sec-boot') {
      return inferredInfo
    }
    if (explicitTag == 'x1-sec-boot' && inferredInfo.tag == 'lenovo-x1') {
      return explicitInfo
    }

    return explicitTag == inferredInfo.tag ? inferredInfo : null
  }

  return inferredInfo
}

private def resolve_catalog_test_target(String deviceTag, String variant, String buildTarget, int idx) {
  def device = device_catalog().get(normalize_optional_string(deviceTag), null)
  if (!(device instanceof Map)) {
    fail("Unknown device_tag '${deviceTag}' for '${buildTarget}' entry #${idx + 1}")
  }

  def variants = device instanceof Map ? device.variants : null
  if (!(variants instanceof Map) || variants.isEmpty()) {
    fail("device_tag '${deviceTag}' does not support variants for '${buildTarget}' entry #${idx + 1}")
  }

  def resolvedTarget = normalize_optional_string(variants.get(variant, null))
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

private def effective_testagent_host(Map testConfig, String defaultHost = null) {
  return normalize_optional_string(testConfig.get('effective_testagent_host', null)) ?:
    normalize_optional_string(testConfig.get('testagent_host_override', null)) ?:
    normalize_optional_string(testConfig.get('testagent_host', null)) ?:
    normalize_optional_string(defaultHost)
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

  def effectiveHost = effective_testagent_host(testConfig)

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

private def test_run(Map normalizedTest, String id, String pathKey, boolean secureboot, String skipReason = null) {
  def run = shallow_copy_map(normalizedTest)
  run.id = id
  run.test_path_key = pathKey
  run.secureboot = secureboot
  run.artifacts = "test-results/${pathKey}"
  if (skipReason != null) {
    run.initial_status = 'SKIPPED'
    run.initial_reason = skipReason
  }
  return run
}

private def expand_test_runs(
  String buildTarget,
  List normalizedTests,
  String ciEnv,
  boolean securebootExecutionAllowed) {
  if (!(buildTarget instanceof String) || buildTarget.isEmpty()) {
    fail("Missing target name")
  }
  def runs = []

  normalizedTests.each { normalizedTest ->
    def skipReason = ciEnv == 'vm' ? 'ci_env_vm' : null
    runs << test_run(
      normalizedTest,
      normalizedTest.id,
      normalizedTest.test_path_key,
      false,
      skipReason
    )

    if (normalizedTest.secureboot_requested) {
      runs << test_run(
        normalizedTest,
        normalizedTest.secureboot_id,
        normalizedTest.secureboot_test_path_key,
        true,
        skipReason ?: (securebootExecutionAllowed ? null : 'secureboot_not_available')
      )
    }
  }

  def preferredStageGroups = [:]
  runs.each { run ->
    def preferredStageName = test_stage_name(run, display_device_tag(run) ?: target_stage_subject(run))
    run.stage_name = preferredStageName
    preferredStageGroups[preferredStageName] = (preferredStageGroups[preferredStageName] ?: []) + [run]
  }

  preferredStageGroups.each { String stageName, List<Map> groupedRuns ->
    if (groupedRuns.size() > 1) {
      groupedRuns.each { run ->
        run.stage_name = test_stage_name(run, target_stage_subject(run))
      }
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
  normalized.shortname = short_target_name(targetName)
  normalized.no_image = normalized.get('no_image', false)
  def uefiSignRequested = normalized.get('uefisign', false) || normalized.get('uefisigniso', false)
  normalized.uefi_sign_requested = uefiSignRequested
  normalized.provenance_requested = normalized.get('provenance', true)
  normalized.build_otapin_requested = normalized.get('build_otapin', false)
  normalized.sbom_requested = normalized.get('sbom', false)
  normalized.tests = normalize_tests(normalized, defaultTestagentHost)
  normalized.test_runs = expand_test_runs(
    targetName,
    normalized.tests,
    ciEnv,
    !normalized.no_image && signingPossible && uefiSignRequested && ciEnv == "prod"
  )
  return normalized
}
