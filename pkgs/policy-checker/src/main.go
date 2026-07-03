// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/goccy/go-yaml"
	"github.com/google/cel-go/cel"
	"github.com/urfave/cli/v3"
)

const (
	releaseAttestationType = "https://ghaf.tii.ae/attestation/release-policy/v1"
	releasePredicateType   = "https://ghaf.tii.ae/predicate/release-policy/v1"
)

type Criteria struct {
	Id          string `json:"id" yaml:"id"`
	Cel         string `json:"cel" yaml:"cel"`
	Description string `json:"description" yaml:"description"`
	Required    bool   `json:"required" yaml:"required"`
}

type SignaturePolicy struct {
	Verify bool `json:"verify" yaml:"verify"`
}

type TrustPolicy struct {
	Name      string          `json:"name" yaml:"name"`
	URI       string          `json:"uri" yaml:"uri"`
	Version   string          `json:"version" yaml:"version"`
	Signature SignaturePolicy `json:"signature" yaml:"signature"`
	Criteria  []Criteria      `json:"criteria" yaml:"criteria"`
}

type CriterionResult struct {
	CriterionID string `json:"criterion_id"`
	Description string `json:"description,omitempty"`
	Required    bool   `json:"required"`
	Status      string `json:"status"`
	Details     string `json:"details,omitempty"`
}

func readJSON(path string) (map[string]any, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var input map[string]any
	if err := json.Unmarshal(raw, &input); err != nil {
		return nil, err
	}
	return input, nil
}

func readPolicy(path string) (TrustPolicy, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return TrustPolicy{}, err
	}
	var config TrustPolicy
	if err := yaml.Unmarshal(raw, &config); err != nil {
		return TrustPolicy{}, err
	}
	return config, nil
}

func fileSHA256(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:]), nil
}

func verifySignature(mode string, artifact string, signature string) error {
	cmd := exec.Command("verify-signature", mode, artifact, signature)
	var stderr bytes.Buffer
	var stdout bytes.Buffer
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout
	err := cmd.Run()
	fmt.Print(stdout.String())
	if err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("verification command failed: %s", message)
	}
	return nil
}

func evaluateCriteria(
	input map[string]any,
	criteria []Criteria,
	variables ...cel.EnvOption,
) ([]CriterionResult, bool, error) {
	// Declare the CEL environment.
	env, err := cel.NewEnv(variables...)
	if err != nil {
		return nil, false, fmt.Errorf("environment declaration error: %w", err)
	}

	failures := false
	results := []CriterionResult{}
	for _, criterion := range criteria {
		result := CriterionResult{
			CriterionID: criterion.Id,
			Description: criterion.Description,
			Required:    criterion.Required,
		}

		fmt.Printf(":: %s\n", criterion.Description)
		ast, issues := env.Compile(criterion.Cel)
		if issues != nil && issues.Err() != nil {
			return nil, false, fmt.Errorf("type-check error in %q: %w", criterion.Id, issues.Err())
		}

		prg, err := env.Program(ast)
		if err != nil {
			return nil, false, fmt.Errorf("program construction error in %q: %w", criterion.Id, err)
		}

		// Evaluate.
		out, _, err := prg.Eval(input)
		if err != nil {
			return nil, false, fmt.Errorf("evaluation error in %q: %w", criterion.Id, err)
		}

		pass, ok := out.Value().(bool)
		if !ok {
			return nil, false, fmt.Errorf("criterion %q did not evaluate to a boolean", criterion.Id)
		}
		fmt.Printf("-> %v\n\n", pass)

		if pass {
			result.Status = "pass"
		} else {
			result.Status = "fail"
			if criterion.Required {
				failures = true
			}
		}
		results = append(results, result)
	}

	return results, failures, nil
}

func provenanceVariables() []cel.EnvOption {
	return []cel.EnvOption{
		cel.Variable("_type", cel.StringType),
		cel.Variable("predicateType", cel.StringType),
		// subject and predicate are dynamic to avoid verbose type specification.
		cel.Variable("subject", cel.ListType(cel.DynType)),
		cel.Variable("predicate", cel.DynType),
		cel.Variable("now", cel.TimestampType),
	}
}

func provenanceCheck(provenanceFile string, config TrustPolicy) ([]CriterionResult, bool, error) {
	// Read and unmarshal the provenance file into a map.
	input, err := readJSON(provenanceFile)
	if err != nil {
		return nil, false, err
	}
	// Add current time into the input so it can be used in queries.
	input["now"] = time.Now()
	fmt.Printf("Current time is: %s\n\n", input["now"])
	return evaluateCriteria(input, config.Criteria, provenanceVariables()...)
}

func stringAt(root any, keys ...string) string {
	current := root
	for _, key := range keys {
		asMap, ok := current.(map[string]any)
		if !ok {
			return ""
		}
		current = asMap[key]
	}
	value, ok := current.(string)
	if !ok {
		return ""
	}
	return value
}

func fileExists(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func verifyFileSignature(mode string, artifact string, signature string) map[string]any {
	result := map[string]any{
		"verified": false,
		"error":    "",
	}
	if !fileExists(artifact) {
		result["error"] = fmt.Sprintf("missing artifact: %s", artifact)
		return result
	}
	if !fileExists(signature) {
		result["error"] = fmt.Sprintf("missing signature: %s", signature)
		return result
	}
	if err := verifySignature(mode, artifact, signature); err != nil {
		result["error"] = err.Error()
		return result
	}
	result["verified"] = true
	return result
}

func releaseVariables() []cel.EnvOption {
	return []cel.EnvOption{
		cel.Variable("manifest", cel.DynType),
		cel.Variable("oci", cel.DynType),
		cel.Variable("provenance", cel.DynType),
		cel.Variable("test_results", cel.DynType),
		cel.Variable("files", cel.DynType),
		cel.Variable("signatures", cel.DynType),
		cel.Variable("provenance_policy", cel.DynType),
		cel.Variable("now", cel.TimestampType),
	}
}

func digestMap(digest string) map[string]string {
	parts := strings.SplitN(digest, ":", 2)
	if len(parts) != 2 {
		return map[string]string{}
	}
	return map[string]string{parts[0]: parts[1]}
}

func releasePolicyInput(
	targetDir string,
	ociResultPath string,
) (map[string]any, map[string]any, map[string]any, error) {
	manifestPath := filepath.Join(targetDir, "manifest.json")
	manifest, err := readJSON(manifestPath)
	if err != nil {
		return nil, nil, nil, err
	}
	ociResult, err := readJSON(ociResultPath)
	if err != nil {
		return nil, nil, nil, err
	}

	testResultsPath := filepath.Join(targetDir, "test-results.json")
	testResults := map[string]any{
		"configured": false,
		"tests":      []any{},
	}
	if fileExists(testResultsPath) {
		testResults, err = readJSON(testResultsPath)
		if err != nil {
			return nil, nil, nil, err
		}
		testResults["configured"] = true
	}

	images := []any{}
	rawImages, hasImages := manifest["images"]
	if hasImages && rawImages != nil {
		if imageList, ok := rawImages.([]any); ok {
			images = imageList
		}
	} else if image, ok := manifest["image"]; ok {
		images = []any{image}
	}
	imageExists := len(images) > 0
	imageSignatureExists := len(images) > 0
	imageSignaturesVerified := len(images) > 0
	imageSignatureErrors := []string{}
	for _, image := range images {
		imagePath := filepath.Join(targetDir, stringAt(image, "path"))
		imageSignaturePath := filepath.Join(targetDir, stringAt(image, "signature", "path"))
		imageSignature := verifyFileSignature("image", imagePath, imageSignaturePath)

		if !fileExists(imagePath) {
			imageExists = false
		}
		if !fileExists(imageSignaturePath) {
			imageSignatureExists = false
		}
		if verified, ok := imageSignature["verified"].(bool); !ok || !verified {
			imageSignaturesVerified = false
			if message, ok := imageSignature["error"].(string); ok && message != "" {
				imageSignatureErrors = append(imageSignatureErrors, message)
			}
		}
	}
	provenancePath := filepath.Join(targetDir, stringAt(manifest, "attestations", "provenance", "path"))
	provenanceSignaturePath := filepath.Join(targetDir, stringAt(manifest, "attestations", "provenance", "signature", "path"))

	provenanceSignature := verifyFileSignature("provenance", provenancePath, provenanceSignaturePath)
	provenance := map[string]any{}
	if fileExists(provenancePath) {
		provenance, err = readJSON(provenancePath)
		if err != nil {
			return nil, nil, nil, err
		}
	}

	provenancePolicy := map[string]any{
		"passed": false,
	}
	if passed, ok := testResults["provenance_policy_passed"].(bool); ok {
		provenancePolicy["passed"] = passed
	}

	sbomCSV := filepath.Join(targetDir, stringAt(manifest, "attestations", "sbom_csv", "path"))
	sbomCycloneDX := filepath.Join(targetDir, stringAt(manifest, "attestations", "sbom_cyclonedx", "path"))
	sbomSPDX := filepath.Join(targetDir, stringAt(manifest, "attestations", "sbom_spdx", "path"))

	input := map[string]any{
		"manifest":     manifest,
		"oci":          ociResult,
		"provenance":   provenance,
		"test_results": testResults,
		"files": map[string]any{
			"image":           imageExists,
			"image_signature": imageSignatureExists,
			"provenance":      fileExists(provenancePath),
			"provenance_signature": fileExists(
				provenanceSignaturePath,
			),
			"sbom_csv":       fileExists(sbomCSV),
			"sbom_cyclonedx": fileExists(sbomCycloneDX),
			"sbom_spdx":      fileExists(sbomSPDX),
		},
		"signatures": map[string]any{
			"image": map[string]any{
				"verified": imageSignaturesVerified,
				"error":    strings.Join(imageSignatureErrors, "; "),
			},
			"provenance": provenanceSignature,
		},
		"provenance_policy": provenancePolicy,
		"now":               time.Now(),
	}
	return input, manifest, ociResult, nil
}

func evaluateReleasePolicy(
	targetDir string,
	ociResultPath string,
	policyPath string,
) (map[string]any, bool, error) {
	policyDigest, err := fileSHA256(policyPath)
	if err != nil {
		return nil, false, err
	}
	policy, err := readPolicy(policyPath)
	if err != nil {
		return nil, false, err
	}
	input, manifest, ociResult, err := releasePolicyInput(
		targetDir,
		ociResultPath,
	)
	if err != nil {
		return nil, false, err
	}

	results, failures, err := evaluateCriteria(input, policy.Criteria, releaseVariables()...)
	if err != nil {
		return nil, false, err
	}

	primary := ociResult["primary"]
	digest := stringAt(primary, "digest")
	reference := stringAt(primary, "reference")
	attestation := map[string]any{
		"_type":         releaseAttestationType,
		"predicateType": releasePredicateType,
		"subject": []map[string]any{
			{
				"name":   reference,
				"digest": digestMap(digest),
			},
		},
		"predicate": map[string]any{
			"policy": map[string]any{
				"name":    policy.Name,
				"uri":     policy.URI,
				"version": policy.Version,
				"digest": map[string]string{
					"sha256": policyDigest,
				},
			},
			"artifact": map[string]any{
				"target":     manifest["target"],
				"repository": ociResult["repository"],
				"reference":  reference,
				"digest":     digest,
			},
			"source":      manifest["source"],
			"passed":      !failures,
			"results":     results,
			"timestamp":   time.Now().UTC().Format(time.RFC3339),
			"attested_by": "policy-checker",
		},
	}
	return attestation, failures, nil
}

func writeAttestation(path string, attestation map[string]any) error {
	raw, err := json.MarshalIndent(attestation, "", "  ")
	if err != nil {
		return err
	}
	raw = append(raw, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o644)
}

func runProvenanceAction(cmd *cli.Command) error {
	provenanceFile := cmd.StringArg("provenance")
	provenanceSignature := cmd.String("sig")
	configFile := cmd.String("policy")

	if provenanceFile == "" {
		return errors.New("provenance file must be provided")
	}
	if configFile == "" {
		return errors.New("trust policy file must be provided")
	}

	config, err := readPolicy(configFile)
	if err != nil {
		return err
	}

	if config.Signature.Verify {
		if provenanceSignature == "" {
			return errors.New("trust policy requires verified signature, but no signature file was provided")
		}
		fmt.Println("Verifying signature")
		if err := verifySignature("provenance", provenanceFile, provenanceSignature); err != nil {
			return err
		}
	}

	fmt.Println()
	_, failures, err := provenanceCheck(provenanceFile, config)
	if err != nil {
		return err
	}
	if failures {
		return errors.New("some required checks did not pass")
	}
	return nil
}

func releaseCommand() *cli.Command {
	return &cli.Command{
		Name:      "release",
		Usage:     "Evaluate release policy and emit a release attestation",
		UsageText: "policy-checker release TARGET_DIR --oci-result FILE --policy FILE --out FILE",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:     "oci-result",
				Usage:    "OCI publish result `FILE`.",
				Required: true,
			},
			&cli.StringFlag{
				Name:     "policy",
				Usage:    "Release policy `FILE`.",
				Required: true,
			},
			&cli.StringFlag{
				Name:     "out",
				Usage:    "Output release attestation `FILE`.",
				Required: true,
			},
		},
		Arguments: []cli.Argument{
			&cli.StringArg{
				Name:      "target-dir",
				UsageText: "Target artifact directory.",
			},
		},
		Action: func(ctx context.Context, cmd *cli.Command) error {
			targetDir := cmd.StringArg("target-dir")
			if targetDir == "" {
				return errors.New("target artifact directory must be provided")
			}
			attestation, failures, err := evaluateReleasePolicy(
				targetDir,
				cmd.String("oci-result"),
				cmd.String("policy"),
			)
			if err != nil {
				return err
			}
			if err := writeAttestation(cmd.String("out"), attestation); err != nil {
				return err
			}
			fmt.Printf("[+] Wrote release attestation: %s\n", cmd.String("out"))
			if failures {
				return errors.New("some required release policy checks did not pass")
			}
			return nil
		},
	}
}

func main() {
	cmd := &cli.Command{
		Name:      "policy-checker",
		Usage:     "Verify SLSA provenance or release policy",
		UsageText: "policy-checker PROVENANCE_FILE [--sig FILE --policy FILE]",
		Commands:  []*cli.Command{releaseCommand()},
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:  "sig",
				Value: "",
				Usage: "Signature `FILE` to verify the provenance with.",
			},
			&cli.StringFlag{
				Name:  "policy",
				Value: "",
				Usage: "`FILE` containing the trust policy configuration.",
			},
		},
		Arguments: []cli.Argument{
			&cli.StringArg{
				Name:      "provenance",
				UsageText: "Path to the provenance file to be verified.",
			},
		},
		Action: func(ctx context.Context, cmd *cli.Command) error {
			return runProvenanceAction(cmd)
		},
	}

	if err := cmd.Run(context.Background(), os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %s\n", err)
		os.Exit(1)
	}
}
