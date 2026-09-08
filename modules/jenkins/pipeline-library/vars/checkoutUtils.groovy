// SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

@NonCPS
private def looks_like_hex_ref(String value) {
  return value ==~ /(?i)[0-9a-f]{7,40}/
}

@NonCPS
private def trim_prefix(String value, String prefix) {
  return value.startsWith(prefix) ? value.substring(prefix.length()) : value
}

private def remote_ref_exists(String repoUrl, String scope, String refName) {
  def quotedRepo = artifactSupport.shell_quote(repoUrl)
  def quotedRef = artifactSupport.shell_quote(refName)
  return sh(
    script: "git ls-remote --exit-code --${scope} --refs ${quotedRepo} ${quotedRef} >/dev/null 2>&1",
    returnStatus: true
  ) == 0
}

private def with_checkout_retry(String repoUrl, String requestedRef, Closure body) {
  retry(3) {
    echo "Preparing clean checkout of '${requestedRef}' from ${repoUrl}"
    deleteDir()
    body()
  }
}

@NonCPS
private def git_clone_extension(Map args = [:]) {
  def extension = [
    $class: 'CloneOption',
    shallow: args.get('shallow', false),
    noTags: args.get('noTags', true),
    timeout: args.get('timeout', 30),
    honorRefspec: args.get('honorRefspec', true),
  ]
  if (args.containsKey('depth') && args.depth != null) {
    extension.depth = args.depth
  }
  return extension
}

private def checkout_origin_ref(String repoUrl, String branchName, String refspec, Map cloneArgs = [:]) {
  checkout scmGit(
    branches: [[name: branchName]],
    userRemoteConfigs: [[
      url: repoUrl,
      name: 'origin',
      refspec: refspec,
    ]],
    extensions: [
      git_clone_extension(cloneArgs + [timeout: 30, honorRefspec: true]),
    ],
  )
}

private def checkout_branch(String repoUrl, String branchName) {
  checkout_origin_ref(
    repoUrl,
    "origin/${branchName}",
    "+refs/heads/${branchName}:refs/remotes/origin/${branchName}",
    [shallow: true, noTags: true, depth: 50]
  )
}

private def checkout_tag(String repoUrl, String tagName) {
  checkout_origin_ref(
    repoUrl,
    "refs/tags/${tagName}",
    "+refs/tags/${tagName}:refs/tags/${tagName}",
    [shallow: false, noTags: false]
  )
}

private def checkout_flexible_ref(String repoUrl, String requestedRef) {
  // Commit SHAs and other unresolved refs need the git plugin's broader ref discovery path.
  checkout scmGit(
    branches: [[name: requestedRef]],
    userRemoteConfigs: [[url: repoUrl]],
    extensions: [
      git_clone_extension(shallow: false, noTags: false, timeout: 30, honorRefspec: false),
    ],
  )
}

def checkout_ci_test_sources(
  String pinned_source_file,
  boolean use_flake_pinned_ci_test,
  String ci_test_repo_branch,
  String ci_test_repo_url) {
  if (use_flake_pinned_ci_test) {
    // The pinned-source file lives on the controller outside the workspace.
    def pinned_src = artifactSupport.run_cmd("cat ${artifactSupport.shell_quote(pinned_source_file)}")
    println("Using flake-pinned ci-test-automation source: ${pinned_src}")
    sh """
      if [ ! -d "${pinned_src}/Robot-Framework/test-suites" ]; then
        echo "ERROR: invalid ci-test-automation source path '${pinned_src}'"
        exit 1
      fi
      cp -r "${pinned_src}/." .
      chmod -R u+w .
    """
    return
  }
  // CI test sources may be pinned to a branch, tag, commit, or GitHub synthetic PR ref.
  checkout_remote_ref(ci_test_repo_url, ci_test_repo_branch, true)
}

def checkout_remote_ref(String repoUrl, String requestedRef, boolean allowSyntheticRefs = false) {
  def normalizedRef = requestedRef?.trim()
  if (!normalizedRef) {
    error("Missing git reference for repository '${repoUrl}'")
  }
  if (normalizedRef.startsWith('refs/pull/') && !allowSyntheticRefs) {
    error(
      "GitHub pull refs like '${normalizedRef}' are not supported here. " +
      "Use a branch, tag, or commit ref, or use a PR-specific pipeline " +
      "that propagates the pull ref downstream."
    )
  }

  with_checkout_retry(repoUrl, normalizedRef) {
    if (normalizedRef.startsWith('refs/heads/')) {
      def branchName = trim_prefix(normalizedRef, 'refs/heads/')
      echo "Checking out branch ref '${normalizedRef}' from ${repoUrl}"
      checkout_branch(repoUrl, branchName)
      return
    }

    if (normalizedRef.startsWith('refs/tags/')) {
      def tagName = trim_prefix(normalizedRef, 'refs/tags/')
      echo "Checking out tag ref '${normalizedRef}' from ${repoUrl}"
      checkout_tag(repoUrl, tagName)
      return
    }

    if (normalizedRef.startsWith('refs/pull/')) {
      echo "Checking out exact ref '${normalizedRef}' from ${repoUrl}"
      checkout_origin_ref(
        repoUrl,
        'refs/remotes/origin/selected-ref',
        "+${normalizedRef}:refs/remotes/origin/selected-ref",
        [shallow: false, noTags: true]
      )
      return
    }

    def branchName = normalizedRef
    branchName = trim_prefix(branchName, 'refs/remotes/origin/')
    branchName = trim_prefix(branchName, 'remotes/origin/')
    branchName = trim_prefix(branchName, 'origin/')
    if (remote_ref_exists(repoUrl, 'heads', "refs/heads/${branchName}")) {
      echo "Checking out branch '${branchName}' from ${repoUrl}"
      checkout_branch(repoUrl, branchName)
      return
    }

    def tagName = trim_prefix(normalizedRef, 'refs/tags/')
    if (remote_ref_exists(repoUrl, 'tags', "refs/tags/${tagName}")) {
      echo "Checking out tag '${tagName}' from ${repoUrl}"
      checkout_tag(repoUrl, tagName)
      return
    }

    def reason = looks_like_hex_ref(normalizedRef) ? 'hex-looking ref' : 'unresolved ref'
    echo "Falling back to flexible checkout for ${reason} '${normalizedRef}' from ${repoUrl}"
    checkout_flexible_ref(repoUrl, normalizedRef)
  }
}

def checkout_github_pr_merge(String repoUrl, String prNumber, String targetBranch = null, List extraExtensions = []) {
  def normalizedPr = prNumber?.trim()
  if (!normalizedPr) {
    error("Missing PR number for repository '${repoUrl}'")
  }
  def normalizedTargetBranch = targetBranch?.trim()
  def mergeRef = "refs/pull/${normalizedPr}/merge"
  def headRef = "refs/pull/${normalizedPr}/head"
  def refspecs = [
    "+${mergeRef}:refs/remotes/pr_origin/pull/${normalizedPr}/merge",
    "+${headRef}:refs/remotes/pr_origin/pull/${normalizedPr}/head",
  ]
  if (normalizedTargetBranch) {
    refspecs << "+refs/heads/${normalizedTargetBranch}:refs/remotes/origin/${normalizedTargetBranch}"
  }

  with_checkout_retry(repoUrl, "PR ${normalizedPr}") {
    checkout scmGit(
      branches: [[name: "refs/remotes/pr_origin/pull/${normalizedPr}/merge"]],
      userRemoteConfigs: [[
        url: repoUrl,
        name: 'pr_origin',
        refspec: refspecs.join(' '),
      ]],
      extensions: [
        git_clone_extension(shallow: false, noTags: true, timeout: 30, honorRefspec: true),
      ] + extraExtensions,
    )
  }
}
