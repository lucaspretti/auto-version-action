# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitHub Actions **composite action** for automated semantic versioning driven by Conventional Commits. Pure bash, no build step, no npm dependencies. Designed for a two-branch workflow: staging (RC pre-releases) and production (final releases).

## Architecture

**`action.yml`** — Composite action entry point. Defines inputs/outputs and orchestrates six sequential steps, each calling a script from `scripts/`. All inter-step communication flows through `$GITHUB_OUTPUT` environment variables.

**`scripts/` pipeline** (executed in order):

0. **`version-utils.sh`** — Shared library sourced by other scripts. Provides `detect_version_file_type`, `read_version`, and `write_version` functions. Auto-detects file format by filename (JSON via `jq`, TOML/YAML via `sed`/`grep`, plain text via `cat`/`echo`).
1. **`analyze-commits.sh`** — Scans commits since last production tag using regex against conventional commit prefixes. Filters out `[skip ci]` commits before classification to avoid phantom bumps from automated commits. Detects `<type>!:` on any commit type for breaking changes (not just `feat!:`). Tolerates issue reference prefixes (e.g., `#123 feat:`). Outputs `type` (major/minor/patch/none) and `is_subsequent_rc` (whether RC tags already exist for this version). When all commits are `[skip ci]`, outputs `type=none` and all downstream steps skip gracefully.
2. **`bump-version.sh`** — On staging: bumps version file via `version-utils.sh`, optionally updates Helm `Chart.yaml` `appVersion`, handles version escalation (higher-priority bump resets RC to 1), commits with `[skip ci]`, and pushes. On production: uses semver comparison (`version_gte`) to check if version is already correct or higher (from staging merge); only bumps if truly outdated (direct push). When `type=none`, skips entirely on both branches.
3. **`create-release.sh`** — Creates GitHub releases via REST API. On staging: pre-release with RC tag. On production: full release. Both include categorized changelogs (Breaking/Features/Fixes/Maintenance/Other).
4. **`cleanup-rc.sh`** — Production only. Deletes RC pre-releases with version <= current via GitHub API. Preserves higher-version RCs from escalation scenarios.
5. **`update-floating-tags.sh`** — Production only, opt-in (`update-floating-tags: "true"`). Moves `vMAJOR` and `vMAJOR.MINOR` tags to the latest release. Useful for GitHub Actions consumed via `@v1`.
6. **Sync step** (inline in `action.yml`) — Production only. Merges production back to staging (skipped if staging branch doesn't exist).
7. **`summary.sh`** — Writes formatted step summary to `$GITHUB_STEP_SUMMARY`.

## Key Design Concepts

**Version escalation**: When a higher-priority commit type appears mid-RC cycle, the base version re-bumps and RC resets to 1. Priority order: major (3) > minor (2) > patch (1).

**Idempotent re-runs**: Scripts handle existing tags/releases (delete-and-recreate pattern).

**No-tag fallback**: When no production tag exists (first release), commit analysis starts from the repo's root commit (`git rev-list --max-parents=0 HEAD`). The `ROOT..HEAD` range excludes the root commit itself, so a repo with only one commit produces `type=none` (no release). The first release requires at least two commits.

**Environment variable contract**: `action.yml` passes inputs/context to scripts via `env` blocks. Scripts read `INPUT_*` and `GITHUB_*` vars, write outputs to `$GITHUB_OUTPUT`.

## Runtime Requirements

Scripts expect these tools available on the runner: `bash`, `jq`, `sed`, `git` (with full history via `fetch-depth: 0`), `curl`.

## Workflow Modes

Supports both **two-branch** (staging -> production with RC releases) and **single-branch** (production only, direct bump + release). Same action config, difference is only which branches trigger the workflow.

## GHES Notes

- Always set `github-api-url: ${{ github.api_url }}` for GitHub Enterprise Server
- Use your self-hosted runner label instead of `ubuntu-latest`

## Testing

Unit tests live in `tests/` and run via `bash tests/run-all.sh`. Tests use a minimal bash assertion helper (`tests/test-helper.sh`), no external framework. Each script has a corresponding test file (e.g., `tests/test-bump-version.sh`). Tests mock git/GitHub API calls and validate logic in isolation.

Run tests locally: `bash tests/run-all.sh`

**MANDATORY: Always run `bash tests/run-all.sh` after modifying any script in `scripts/` or `tests/`. All tests must pass before committing. If a test fails, fix the issue before proceeding.**

## Conventions

- All scripts use `set -euo pipefail`
- Commits created by the action use `[skip ci]` to prevent recursive triggers
- Changelogs exclude `[skip ci]` commits (automated bumps/syncs)
- Commit analysis filters out `[skip ci]` commits before type classification to prevent phantom bumps (e.g., repeated staging-to-master merges that only carry automated sync/bump commits)
- Git identity is set to `github-actions[bot]`
- RC tags follow `v{major}.{minor}.{patch}-rc.{n}` format; production tags follow `v{major}.{minor}.{patch}`
- Use `printf -- '...'` when format strings start with `-` to prevent bash interpreting them as options
