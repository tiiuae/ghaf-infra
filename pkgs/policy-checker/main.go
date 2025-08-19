// SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"time"

	"github.com/google/cel-go/cel"
	"github.com/urfave/cli/v3"
)

type Criteria struct {
	Id          string
	Cel         string
	Description string
	Required    bool
}

type SignaturePolicy struct {
	Certificate  string
	Verifier_rev string
	Verify       bool
}

type TrustPolicy struct {
	Version   string
	Signature SignaturePolicy
	Criteria  []Criteria
}

func VerifySignature(provenance_file string, provenance_signature string, policy SignaturePolicy) {
	fmt.Println("Verifying signature...")
	cmd := exec.Command(
		"nix", "run", fmt.Sprintf("github:tiiuae/ci-yubi/%s#verify", policy.Verifier_rev), "--",
		"--cert", policy.Certificate,
		"--path", provenance_file,
		"--sigfile", provenance_signature,
	)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		fmt.Println(stderr.String())
		os.Exit(1)
	}

	fmt.Println("Signature OK")
}

func provenanceCheck(provenance_file string, config TrustPolicy) {
	// Read and unmarshal the provenance file into a map
	raw, err := os.ReadFile(provenance_file)
	if err != nil {
		panic(err)
	}
	var input map[string]any
	_ = json.Unmarshal(raw, &input)

	// Declare the CEL environment
	env, err := cel.NewEnv(
		cel.Variable("_type", cel.StringType),
		cel.Variable("predicateType", cel.StringType),
		// subject and predicate are dynamic to avoid verbose type specification
		cel.Variable("subject", cel.ListType(cel.DynType)),
		cel.Variable("predicate", cel.DynType),
		cel.Variable("now", cel.TimestampType),
	)
	if err != nil {
		panic(fmt.Sprintf("environment declaration error: %s", err))
	}

	// add current time into the input so it can be used in the queries
	input["now"] = time.Now()
	fmt.Printf("Current time is: %s\n\n", input["now"])

	failures := false
	for _, ruleset := range config.Criteria {
		fmt.Printf(":: %s\n", ruleset.Description)

		ast, issues := env.Compile(ruleset.Cel)
		if issues != nil && issues.Err() != nil {
			panic(fmt.Sprintf("type-check error: %s", issues.Err()))
		}

		prg, err := env.Program(ast)
		if err != nil {
			panic(fmt.Sprintf("program construction error: %s", err))
		}

		// Evaluate
		out, _, err := prg.Eval(input)
		if err != nil {
			panic(fmt.Sprintf("evaluation error: %s", err))
		}

		pass := out.Value().(bool)
		fmt.Printf("-> %v\n\n", pass)

		if !pass && ruleset.Required {
			failures = true
		}
	}

	if failures {
		fmt.Println("Some required checks did not pass!")
		os.Exit(1)
	}
}

func main() {
	cmd := &cli.Command{
		Name:      "Provenance policy checker",
		Usage:     "Verify SLSA provenance file meets policies",
		UsageText: "policy-checker PROVENANCE_FILE [--sig FILE --policy FILE]",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:  "sig",
				Value: "",
				Usage: "Signature `FILE` to verify the provenance with.",
			},
			&cli.StringFlag{
				Name:     "policy",
				Value:    "",
				Usage:    "`FILE` containing the trust policy configuration.",
				Required: true,
			},
		},
		Arguments: []cli.Argument{
			&cli.StringArg{
				Name:      "provenance",
				UsageText: "Path to the provenance file to be verified.",
			},
		},
		Action: func(ctx context.Context, cmd *cli.Command) error {
			provenance_file := cmd.StringArg("provenance")
			provenance_signature := cmd.String("sig")
			config_file := cmd.String("policy")

			if provenance_file == "" {
				fmt.Println("Provenance file must be provided.")
				os.Exit(1)
			}

			// read the trust policy file
			raw, err := os.ReadFile(config_file)
			if err != nil {
				panic(err)
			}
			var config TrustPolicy
			_ = json.Unmarshal(raw, &config)

			if config.Signature.Verify {
				if provenance_signature != "" {
					VerifySignature(provenance_file, provenance_signature, config.Signature)
				} else {
					fmt.Println("Trust policy requires verified signature, but no signature file was provided.")
					os.Exit(1)
				}
			}

			fmt.Println()
			provenanceCheck(provenance_file, config)

			return nil
		},
	}

	if err := cmd.Run(context.Background(), os.Args); err != nil {
		panic(err)
	}
}
