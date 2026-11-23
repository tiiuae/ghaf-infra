// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
package main

import (
	"os"
	"testing"
)

func TestReleaseImagePolicyCompatibility(t *testing.T) {
	policyPath := os.Getenv("RELEASE_POLICY_FILE")
	if policyPath == "" {
		policyPath = "../../../slsa/release-policy.yaml"
	}
	policy, err := readPolicy(policyPath)
	if err != nil {
		t.Fatal(err)
	}
	var criteria []Criteria
	for _, criterion := range policy.Criteria {
		if criterion.Id == "image-signature" {
			criteria = append(criteria, criterion)
		}
	}
	if len(criteria) != 1 {
		t.Fatal("missing image-signature criterion")
	}
	image := map[string]any{"signature": map[string]any{"signing_key": policy.SigningKeys["image"][0]}}
	for _, test := range []struct {
		name        string
		manifest    map[string]any
		wantFailure bool
	}{
		{"v2", map[string]any{"image": image}, false},
		{"v1", map[string]any{"images": []any{image, image}}, false},
		{"v1-unauthorized-second-key", map[string]any{"images": []any{image,
			map[string]any{"signature": map[string]any{"signing_key": "unauthorized"}},
		}}, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			input := map[string]any{
				"manifest":     test.manifest,
				"signing_keys": policy.SigningKeys,
				"files":        map[string]any{"image": true, "image_signature": true},
				"signatures":   map[string]any{"image": map[string]any{"verified": true}},
			}
			_, failures, err := evaluateCriteria(input, criteria, releaseVariables()...)
			if err != nil {
				t.Fatal(err)
			}
			if failures != test.wantFailure {
				t.Fatalf("policy failures = %v, want %v", failures, test.wantFailure)
			}
		})
	}
}
