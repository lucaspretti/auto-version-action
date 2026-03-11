# Add Unit Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add comprehensive unit tests for all scripts in the auto-version-action pipeline.

**Architecture:** Each script gets a dedicated test file in `tests/`. Pure bash tests using the minimal `tests/test-helper.sh` assertion framework. Tests mock external dependencies (git, curl, GitHub API) to validate logic in isolation. `tests/run-all.sh` runs everything.

**Tech Stack:** Bash, no external test frameworks.

---

## Done

- `tests/test-helper.sh` - assertion framework
- `tests/run-all.sh` - test runner
- `tests/test-version-utils.sh` - detect_version_file_type, read_version, write_version (all formats)
- `tests/test-bump-version.sh` - get_bump_priority, version_gte (including the downgrade bug regression test)

## Remaining

### Task 1: test-analyze-commits.sh

**Files:**
- Create: `tests/test-analyze-commits.sh`

Test the commit message classification logic in isolation. Extract the grep-based detection into a testable function, or feed commit messages via stdin mock.

**Cases to cover:**
- [ ] `feat!:` and `BREAKING CHANGE` footer detected as major
- [ ] `feat:` and `feat(scope):` detected as minor
- [ ] `fix:`, `chore:`, `docs:`, `refactor:` detected as patch
- [ ] Mixed commits: highest priority wins (feat + fix = minor, feat! + feat = major)
- [ ] `[skip ci]` commits in the mix don't affect classification
- [ ] Empty commit list defaults to patch

### Task 2: test-bump-version.sh (production path integration)

**Files:**
- Modify: `tests/test-bump-version.sh`

Test the production branch version calculation end-to-end by mocking git and version file I/O.

**Cases to cover:**
- [ ] Two-branch: staging set version correctly, production skips bump
- [ ] Two-branch: staging set higher version than expected, production keeps it (regression for downgrade bug)
- [ ] Single-branch: no previous tag, version file at 0.0.0, bumps correctly
- [ ] Single-branch: previous tag exists, bumps from last tag
- [ ] Version escalation: current version < expected triggers bump

### Task 3: test-bump-version.sh (staging path integration)

**Files:**
- Modify: `tests/test-bump-version.sh`

Test the staging branch logic including RC numbering and version escalation.

**Cases to cover:**
- [ ] First RC: no existing RC tags, creates rc.1
- [ ] Subsequent RC: existing RC tags, increments RC number
- [ ] Version escalation: higher bump type resets RC to 1
- [ ] Escalation priority: patch -> minor -> major

### Task 4: test-create-release.sh

**Files:**
- Create: `tests/test-create-release.sh`

Test changelog generation and release payload construction. Mock curl/API calls.

**Cases to cover:**
- [ ] Changelog categorizes commits correctly (Breaking/Features/Fixes/Maintenance/Other)
- [ ] `[skip ci]` commits excluded from changelog
- [ ] Staging: pre-release flag set, RC tag used
- [ ] Production: full release, production tag used
- [ ] Idempotent: existing release deleted before recreation

### Task 5: test-cleanup-rc.sh

**Files:**
- Create: `tests/test-cleanup-rc.sh`

Test RC cleanup logic. Mock GitHub API responses.

**Cases to cover:**
- [ ] Deletes RC pre-releases with version <= current
- [ ] Preserves higher-version RCs (escalation scenario)
- [ ] No RCs to clean up (no-op)
- [ ] API error handling

### Task 6: test-update-floating-tags.sh

**Files:**
- Create: `tests/test-update-floating-tags.sh`

Test floating tag movement logic. Mock git tag API.

**Cases to cover:**
- [ ] Creates vMAJOR and vMAJOR.MINOR tags
- [ ] Moves existing floating tags to new commit
- [ ] Handles first-ever release (no existing floating tags)

### Task 7: CI integration

**Files:**
- Create: `.github/workflows/tests.yml`

- [ ] Add workflow that runs `bash tests/run-all.sh` on push/PR
- [ ] Runs on `ubuntu-latest` (tests don't need GHES)
