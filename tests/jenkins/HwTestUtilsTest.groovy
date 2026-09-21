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
