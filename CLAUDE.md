# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitHub Actions **composite action** for automated semantic versioning driven by Conventional Commits. Pure bash — no build step, no npm dependencies, no tests. Designed for a two-branch workflow: staging (RC pre-releases) and production (final releases).

## Architecture

**`action.yml`** — Composite action entry point. Defines inputs/outputs and orchestrates six sequential steps, each calling a script from `scripts/`. All inter-step communication flows through `$GITHUB_OUTPUT` environment variables.

**`scripts/` pipeline** (executed in order):

1. **`analyze-commits.sh`** — Scans commits since last production tag using regex against conventional commit prefixes. Outputs `type` (major/minor/patch) and `is_subsequent_rc` (whether RC tags already exist for this version).
2. **`bump-version.sh`** — On staging: bumps `package.json` via `npm version`, optionally updates Helm `Chart.yaml` `appVersion`, handles version escalation (higher-priority bump resets RC to 1), commits with `[skip ci]`, and pushes. On production: checks if version is already correct (from staging merge) or bumps if outdated (direct push).
3. **`create-release.sh`** — Creates GitHub releases via REST API. On staging: pre-release with RC tag. On production: full release. Both include categorized changelogs (Breaking/Features/Fixes/Maintenance/Other).
4. **`cleanup-rc.sh`** — Production only. Deletes RC pre-releases with version ≤ current via GitHub API. Preserves higher-version RCs from escalation scenarios.
5. **Sync step** (inline in `action.yml`) — Production only. Merges production back to staging (skipped if staging branch doesn't exist).
6. **`summary.sh`** — Writes formatted step summary to `$GITHUB_STEP_SUMMARY`.

## Key Design Concepts

**Version escalation**: When a higher-priority commit type appears mid-RC cycle, the base version re-bumps and RC resets to 1. Priority order: major (3) > minor (2) > patch (1).

**Idempotent re-runs**: Scripts handle existing tags/releases (delete-and-recreate pattern).

**Environment variable contract**: `action.yml` passes inputs/context to scripts via `env` blocks. Scripts read `INPUT_*` and `GITHUB_*` vars, write outputs to `$GITHUB_OUTPUT`.

## Runtime Requirements

Scripts expect these tools available on the runner: `bash`, `node`/`npm` (for `npm version`), `jq`, `git` (with full history via `fetch-depth: 0`), `curl`.

## Workflow Modes

Supports both **two-branch** (staging → production with RC releases) and **single-branch** (production only, direct bump + release). Same action config, difference is only which branches trigger the workflow.

## CI/CD

This repo uses itself for versioning. Workflow at `.github/workflows/version.yml` runs on `web-default` (GHES self-hosted runner) with `github-api-url: ${{ github.api_url }}` for GHES compatibility.

## Conventions

- All scripts use `set -euo pipefail`
- Commits created by the action use `[skip ci]` to prevent recursive triggers
- Changelogs exclude `[skip ci]` commits (automated bumps/syncs)
- Git identity is set to `github-actions[bot]`
- RC tags follow `v{major}.{minor}.{patch}-rc.{n}` format; production tags follow `v{major}.{minor}.{patch}`
- Use `printf -- '...'` when format strings start with `-` to prevent bash interpreting them as options
