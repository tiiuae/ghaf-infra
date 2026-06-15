// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

@interface NonCPS {}

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
def hwTestUtils = new GroovyShell(this.class.classLoader).parse(
  new File(repoRoot, 'hosts/hetzci/pipeline-library/vars/hwTestUtils.groovy')
)

def expectFailure(String messagePart, Closure body) {
  try {
    body()
    assert false : "Expected failure containing '${messagePart}'"
  } catch (IllegalArgumentException e) {
    assert e.message.contains(messagePart) : "Unexpected message: ${e.message}"
  }
}

assert hwTestUtils.orin_flash_script_attr(
  'packages.aarch64-linux.nvidia-jetson-orin-agx-debug'
) == 'packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64-flash-script'

assert hwTestUtils.orin_flash_script_attr(
  'packages.aarch64-linux.nvidia-jetson-orin-nx-debug'
) == 'packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64-flash-script'

assert hwTestUtils.orin_flash_script_attr(
  'packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64'
) == 'packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64-flash-script'

assert hwTestUtils.orin_flash_script_attr(
  'packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64'
) == 'packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64-flash-script'

expectFailure('Cannot derive Orin flash-script attribute') {
  hwTestUtils.orin_flash_script_attr('packages.x86_64-linux.lenovo-x1-carbon-gen11-debug')
}
