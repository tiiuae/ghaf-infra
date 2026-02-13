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
