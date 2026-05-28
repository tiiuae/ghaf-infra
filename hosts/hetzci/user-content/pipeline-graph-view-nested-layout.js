// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

// Enable the Pipeline Graph View nested layout by default for all users.
try {
  const storageKey = "nestedLayout";
  const reloadKey = "nestedLayoutReloaded";
  if (window.localStorage.getItem(storageKey) !== "true") {
    window.localStorage.setItem(storageKey, "true");
    if (window.sessionStorage.getItem(reloadKey) !== "true") {
      window.sessionStorage.setItem(reloadKey, "true");
      window.location.reload();
    }
  }
} catch (error) {
  console.warn("Failed to enable nested pipeline graph layout", error);
}
