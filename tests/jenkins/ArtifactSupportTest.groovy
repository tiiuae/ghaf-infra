// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def repoRoot = new File(getClass().protectionDomain.codeSource.location.toURI()).parentFile.parentFile.parentFile
def loader = new GroovyClassLoader()
loader.parseClass('@interface NonCPS {}')
def commands = []
def ociManifest = [:]
def support = new GroovyShell(loader, new Binding([
  error: { String message -> throw new IllegalArgumentException(message) },
  readJSON: { Map args -> new JsonSlurper().parseText(args.text) },
  sh: { args ->
    def command = args instanceof Map ? args.script : args
    commands << command.toString()
    command.startsWith('oras manifest fetch') ? JsonOutput.toJson([content: ociManifest]) : ''
  },
])).parse(new File(repoRoot, 'modules/jenkins/pipeline-library/vars/artifactSupport.groovy'))

def expectFailure(String messagePart, Closure body) {
  try {
    body()
    assert false : "Expected failure containing '${messagePart}'"
  } catch (IllegalArgumentException e) {
    assert e.message.contains(messagePart) : e.message
  }
}

['v1', 'v2'].each { version ->
  ociManifest = [config: [mediaType: "application/vnd.ghaf.manifest.${version}+json", digest: 'sha256:1234']]
  assert support.fetch_build_manifest('registry:5000/ghaf/test:tag', 'image') == 'image/manifest.json'
  assert commands.last().endsWith("'registry:5000/ghaf/test@sha256:1234'")
}

def first = [path: 'images/first.img', signature: [path: 'images/first.sig']]
def second = [path: 'images/second.img', signature: [path: 'images/second.sig']]
assert support.main_image([schema_version: 2, image: first]) == first
assert support.main_image([images: [first]]) == first
assert support.main_image([images: [first, second]], second.path) == second
expectFailure('found 2 matching images') { support.main_image([images: [first, second]]) }

def root = java.nio.file.Files.createTempDirectory('image-selection').toFile()
def outside = new File("${root.path}-outside")
support.binding.setVariable('artifactSupport', support)
support.binding.setVariable('sh', { Map args ->
  def process = new ProcessBuilder('bash', '-c', args.script).directory(root).start()
  def output = process.inputStream.text
  def status = process.waitFor()
  if (args.returnStatus) return status
  assert status == 0 : process.errorStream.text
  return output
})
def execution = new GroovyShell(support.binding).parse(new File(repoRoot, 'modules/jenkins/pipeline-library/vars/pipelineExecution.groovy'))

try {
  expectFailure('No main image found') { execution.find_main_image(root.path) }
  new File(root, 'recovery').mkdir()
  new File(root, 'recovery/boot.img').text = 'nested'
  new File(root, 'disk.img.zst').text = 'main'
  assert execution.find_main_image(root.path) == 'disk.img.zst'
  new File(root, 'other.raw').text = 'ambiguous'
  expectFailure('Ambiguous main image') { execution.find_main_image(root.path) }
  assert execution.find_main_image(root.path, 'recovery/boot.img') == 'recovery/boot.img'
  expectFailure("Main image 'typo.img' not found") { execution.find_main_image(root.path, 'typo.img') }
  expectFailure('must stay within') { execution.find_main_image(root.path, '../escape.img') }

  new File(root, 'recovery/boot.img.sig').text = 'signature'
  def quotedPath = "recovery/disk '\$(touch escaped).img"
  new File(root, quotedPath).text = 'quoted filename'
  java.nio.file.Files.createSymbolicLink(new File(root, 'alias.img').toPath(), new File(root, 'recovery/boot.img').toPath())
  ['disk.img.zst', 'recovery/boot.img', 'recovery/boot.img.sig', quotedPath, 'alias.img'].each { path ->
    assert support.downloaded_file(root.path, path) == "${root.path}/${path}"
  }
  assert !new File(root, 'escaped').exists()

  outside.mkdir()
  new File(outside, 'private.img').text = 'outside the download directory'
  java.nio.file.Files.createSymbolicLink(new File(root, 'outside.img').toPath(), new File(outside, 'private.img').toPath())
  java.nio.file.Files.createSymbolicLink(new File(root, 'outside-dir').toPath(), outside.toPath())
  java.nio.file.Files.createSymbolicLink(new File(root, 'missing.img').toPath(), new File(root, 'nonexistent').toPath())
  [
    '', null, '.', 'recovery', 'nonexistent.img', 'missing.img',
    new File(outside, 'private.img').path,
    "../${outside.name}/private.img", 'recovery/../disk.img.zst',
    'outside.img', 'outside-dir/private.img',
  ].each { path ->
    expectFailure('download directory') { support.downloaded_file(root.path, path) }
  }
} finally {
  root.deleteDir()
  outside.deleteDir()
}
