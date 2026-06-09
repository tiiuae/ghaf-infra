<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Repository Guidelines

## Project Structure & Module Organization
This repository is a Nix flake for Ghaf CI/CD infrastructure.

- `hosts/`: host-specific NixOS configs (usually `configuration.nix`, `disk-config.nix`, `secrets.yaml`).
- `services/`: reusable NixOS service modules (`*/default.nix`).
- `users/`: user and team access definitions (`users/*.nix`, `users/teams/*.nix`).
- `nix/`: flake modules for devshell, hooks, deployments, apps, and packages.
- `scripts/`: operational helpers (for build, signing, plugin resolution, user onboarding).
- `docs/`: operational runbooks (`tasks.md`, `deploy-rs.md`, onboarding docs).
- `pkgs/`, `keys/`, `slsa/`: custom packages, key material, and provenance definitions.

## Build, Test, and Development Commands
- `nix develop`: enter the pinned dev shell with all required tools.
- `nix fmt`: run repository formatters.
- `nix flake check --no-build --option allow-import-from-derivation false`: fast CI-aligned evaluation.
- `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`: build one host config locally.

## Coding Style & Naming Conventions
- Nix: format with `nixfmt`; keep module entry files as `default.nix` where practical.
- Python: format with `ruff format`; lint with `pylint`.
- Shell: format with `shfmt --indent 2`; validate with `shellcheck`.
- Keep host/service paths lowercase and hyphenated (for example `hosts/ghaf-monitoring`, `services/remote-build`).

## Code Style: Prefer Compact, Human-Maintainable Code
This repository values straightforward, readable code over excessive abstraction.

When making changes:

- Prefer simple, local, inline code when the logic is only used once.
- Do not introduce helper functions just to name 2-5 lines of obvious logic.
- Create helper functions only when they clearly improve maintainability, for example:
  - the logic is reused in multiple places,
  - the logic has a clear domain meaning,
  - the function hides genuinely complex details,
  - the function makes testing significantly easier,
  - the caller becomes much easier to understand.
- Avoid chains of tiny helper functions where understanding the code requires jumping between many definitions.
- Keep related logic close together unless separation has a clear benefit.
- Prefer explicit control flow over clever abstractions.
- Prefer existing project patterns over introducing new abstractions.
- Avoid speculative generalization. Do not design for future use cases that are not part of the current change.
- Minimize API surface area. Do not export functions, classes, constants, or modules unless they are needed outside the current file/package.
- Before adding a new abstraction, check whether the same result can be achieved by simplifying the surrounding code.

As a rule of thumb:

- Inline code is preferred when it is short, obvious, and used once.
- A helper function is preferred when it removes meaningful duplication, gives a domain concept a useful name, or isolates non-trivial behavior.
- A new class/module is preferred when there is a real state, lifecycle, interface boundary, ownership concern, or a clear reuse/composition benefit that matches existing project patterns.

When reviewing your own changes, ask:

1. Would a maintainer understand this faster if the logic stayed inline?
2. Did I add this helper because it is truly useful, or only because the code looked slightly long?
3. Does this abstraction reduce cognitive load, or does it just move code elsewhere?
4. Is the new structure consistent with nearby code?

If in doubt, choose the simpler and more local implementation.

## Self-review before submitting changes
Before finalizing code changes, review the diff and simplify it where possible.

Look specifically for:

- unnecessary helper functions,
- single-use abstractions,
- unnecessary classes or modules that do not provide clear reuse, composition, or readability benefits,
- overly generic names like `process`, `handle`, `manager`, `helper`, or `utils`,
- logic split across files without a strong reason,
- new configuration or parameters that are not required by the current task,
- changes that make the diff larger than necessary.

Prefer the smallest change that solves the problem cleanly.

## Testing Guidelines
There is no standalone unit-test suite; validation is check-driven.
- Run `nix fmt` to catch formatting/lint issues early.
- Run `nix flake check --option allow-import-from-derivation false --no-build` for checks.
- For host changes, build the target configuration explicitly with `nix build` and verify affected aliases.
- When changing deployment logic, verify `deploy` targets still evaluate.

## Commit & Pull Request Guidelines
- Use concise, imperative commit subjects; optional scopes are common (example: `build(deps): bump ...`).
- Include a `Signed-off-by:` trailer in commit messages (gitlint enforces this rule).
- In PRs, include: affected hosts/services, risk/rollback notes, and command evidence (`nix flake check`, targeted builds, or deploy dry runs).
- If `.github/workflows/*` is changed, explicitly mention manual validation steps; workflow changes have extra scrutiny.
- If secrets or infra access paths change, call that out explicitly in the PR description.

## Security & Configuration Tips
- Never commit plaintext secrets. Store secrets in `secrets.yaml` managed by `sops`.
- After secrets key/rule changes, run `inv update-sops-files`.
- Treat host deployments as destructive operations (`deploy` deploys a new NixOS host configuration).
- Treat `inv install --alias <target>` as destructive: it repartitions and reinstalls the target host.
