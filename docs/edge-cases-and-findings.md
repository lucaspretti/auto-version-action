# Edge Cases & Findings

Lessons learned from real-world usage, initially discovered during the early adopter project integration. This document captures bugs found and fixed, known behaviors, and open items that may need future work.

## Bugs Found & Fixed

### 1. `printf` interprets `---` as option flag

**Symptom**: `printf: --: invalid option` at runtime.

**Cause**: Bash's `printf` builtin interprets arguments starting with `-` as option flags. Format strings like `printf '---\n\n...'` fail because `--` is parsed as an option.

**Fix**: Use `%s` format to pass the `---` as a safe argument:
```bash
# Bad — fails
printf '---\n\n### Deployment\n\n' >> release_notes.md

# Good — works
printf '%s\n\n### Deployment\n\n' '---' >> release_notes.md
```

**Applies to**: Any `printf` call where the format string starts with `-`.

---

### 2. Global tag sort vs ancestor-based tag lookup

**Symptom**: Changelog shows far more commits than expected (e.g., 41 commits when only 3 are relevant).

**Cause**: `git tag -l --sort=-version:refname | head -n 1` picks the highest version tag **globally**, regardless of whether it's reachable from the current branch. If an old tag like `v2.2.0` exists on a different branch, it gets picked instead of the correct ancestor tag `v2.1.0`.

**Fix**: Use `git describe --tags --abbrev=0 --exclude "*-rc.*"` which only finds tags reachable from HEAD (ancestor-based).

```bash
# Bad — picks highest tag globally
LAST_TAG=$(git tag -l --sort=-version:refname | grep -v -E '\-rc\.' | head -n 1)

# Good — picks last tag reachable from current branch
LAST_TAG=$(git describe --tags --abbrev=0 --exclude "*-rc.*" 2>/dev/null || echo "")
```

**Applies to**: `create-release.sh` (staging RC-1 range and production range).

---

### 3. Helm Chart requires existing `appVersion` field

**Symptom**: `sed` silently does nothing, Chart.yaml is unchanged.

**Cause**: The version bump uses `sed -i "s/^appVersion:.*/appVersion: \"$VERSION\"/"` which requires an existing `appVersion` line. If the field doesn't exist in Chart.yaml, sed matches nothing and silently succeeds.

**Fix**: Ensure `appVersion` exists in Chart.yaml before first use. The action does not create the field — it only updates an existing one.

**Potential improvement**: Add a check that appends `appVersion` if missing, or warn the user.

---

### 4. `git describe` uses `creatordate` by default

**Symptom**: Wrong "last production tag" detected after tag deletion and recreation.

**Cause**: If production tags are deleted and recreated (which the action does in re-run scenarios), the creation date resets. `git tag --sort=-creatordate` can give wrong results.

**Fix**: Use `--sort=-version:refname` for semver-based sorting where tag ordering matters (e.g., cleanup script). Use `git describe` for ancestor-based lookups.

---

### 5. YAML block scalar indentation is auto-stripped

**Symptom**: N/A (non-bug — the indentation was correct all along).

**Context**: In GitHub Actions workflows, `run: |` uses YAML block scalars. Content indented under `run: |` has its leading whitespace automatically stripped based on the first content line. Moving content to column 0 **breaks** the YAML because it exits the block scalar scope.

**Lesson**: Never "fix" indentation inside `run: |` blocks — YAML handles it correctly. This was initially identified as a bug in the original workflow but turned out to be a non-issue.

---

### 6. Heredoc quoting prevents variable expansion

**Context**: In the original workflow, production release notes used `<< 'EOF'` (quoted heredoc), which prevents `$VARIABLE` expansion. The workaround was fragile sed/awk substitution after the fact.

**Fix**: The extracted action uses `printf` statements instead of heredocs, avoiding this class of issues entirely. Each line is explicitly formatted with variables as arguments.

---

### 7. `printf` interprets leading `-` in format strings as option flag

**Symptom**: `printf: - : invalid option` when writing list items to release notes.

**Cause**: Same root cause as bug #1, but affects format strings starting with `- ` (markdown list items), e.g. `printf '- **Docker Image**: ...'`.

**Fix**: Use `printf -- '- ...'` where `--` signals end of options:
```bash
# Bad — fails
printf '- **Docker Image**: `%s`\n' "$SHA" >> release_notes.md

# Good — works
printf -- '- **Docker Image**: `%s`\n' "$SHA" >> release_notes.md
```

**Applies to**: `create-release.sh` — all `printf` calls where the format string starts with `- `.

---

### 8. Non-fast-forward push when remote advances during workflow

**Symptom**: `error: failed to push some refs` / `Updates were rejected because the tip of your current branch is behind`.

**Cause**: Between `actions/checkout` and the version bump commit, someone (or another workflow) pushes to the same branch. The bump commit is based on an outdated HEAD, so `git push` fails.

**Fix**: Pull with rebase before pushing:
```bash
git pull --rebase origin "$BRANCH" || true
git push origin "$BRANCH"
```

**Applies to**: `bump-version.sh` — both staging and production push paths.

---

### 9. GHES API returns 401 when using default github-api-url

**Symptom**: `Bad credentials` / HTTP 401 when creating releases on GitHub Enterprise Server.

**Cause**: The `github-api-url` input defaults to `https://api.github.com`. On GHES, the `GITHUB_TOKEN` is only valid for the enterprise instance, not github.com.

**Fix**: Set `github-api-url: ${{ github.api_url }}` in the workflow to auto-detect the correct API endpoint.

**Applies to**: Any GHES deployment. Not an issue on github.com.

---

### 10. Staging sync fails when staging branch doesn't exist

**Symptom**: `fatal: couldn't find remote ref staging` on production release.

**Cause**: The sync step always runs on production releases, but in single-branch (master-only) workflows, the staging branch doesn't exist.

**Fix**: Check if the staging branch exists on remote before attempting sync:
```bash
if git ls-remote --exit-code origin "$INPUT_STAGING_BRANCH" >/dev/null 2>&1; then
  # sync
fi
```

**Applies to**: Single-branch workflows where only the production branch is used.

---

### 11. Floating tag `v1` not updated after new releases

**Symptom**: Consumers using `@v1` don't get bug fixes after new releases.

**Cause**: The `v1` tag was static — created once and never moved. New patch/minor releases create `v1.x.y` tags but don't update the major version floating tag.

**Fix**: Added `update-floating-tags.yml` workflow that triggers on `release: published` and moves `vMAJOR` and `vMAJOR.MINOR` tags to the latest release.

---

### 12. Floating tags picked up by `git describe` as last production tag

**Symptom**: `npm error Invalid version: 1..1` — version parsed incorrectly.

**Cause**: `git describe --tags --abbrev=0 --exclude "*-rc.*"` finds floating tags like `v1` or `v1.1` as the "last production tag". Parsing `v1` gives MAJOR=1, MINOR="", PATCH="", producing invalid versions like `1..1`.

**Fix**: Add `--match "v[0-9]*.[0-9]*.[0-9]*"` to all `git describe` calls so only full semver tags (`vX.Y.Z`) are matched:
```bash
# Bad — picks up v1, v1.1 floating tags
git describe --tags --abbrev=0 --exclude "*-rc.*"

# Good — only matches vX.Y.Z
git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" --exclude "*-rc.*"
```

**Applies to**: Only repos that have floating tags (like this action itself). Other consumer repos are unaffected.

---

### 13. Phantom version bumps from repeated staging-to-master merges

**Symptom**: Production creates a release (e.g., `v0.25.2`) that has no corresponding RC on staging. The RC cycle is still at `v0.25.1-rc.X`.

**Cause**: When staging is merged to master multiple times within the same RC cycle, the second merge carries only automated commits (`chore: bump version [skip ci]`, `chore: sync master back to staging [skip ci]`). The commit analysis saw these as new commits and classified them as `patch`, triggering a spurious version bump.

**Fix**: `analyze-commits.sh` now filters out `[skip ci]` commits before type classification. If no meaningful commits remain after filtering, the script outputs `type=none` and all downstream steps (bump, release, cleanup, floating tags) skip gracefully. Both `bump-version.sh` and `create-release.sh` handle `type=none` with early exits.

**Initial approach (reverted)**: The first fix attempted to check for RC tags in two-branch mode before allowing a production bump. This was abandoned because it would also block legitimate hotfixes pushed directly to master (which have no RC tags by design). Filtering `[skip ci]` at the source is the correct root-cause fix.

**Applies to**: Two-branch workflows (staging + production) with repeated merges.

---

### 14. `HEAD~10` fallback fails on non-linear history

**Symptom**: `fatal: ambiguous argument 'HEAD~10..HEAD'` when running the action on a repo with no previous production tag.

**Cause**: When no production tag exists, `analyze-commits.sh` fell back to `HEAD~10..HEAD` to analyze recent commits. This fails when:
- The commit graph is non-linear (merge commits create ambiguous parent paths for `~N` notation)
- The repo has fewer than 10 commits

**Fix**: Replace `HEAD~10..HEAD` with `ROOT_COMMIT..HEAD`, where `ROOT_COMMIT` is discovered via `git rev-list --max-parents=0 HEAD | head -1`. This works on any history shape and any repo size.

```bash
# Bad -- fails on non-linear history or <10 commits
git log --pretty=%s --no-merges HEAD~10..HEAD

# Good -- works on any history
ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD | head -1)
git log --pretty=%s --no-merges "$ROOT_COMMIT..HEAD"
```

**Note**: The `ROOT..HEAD` range excludes the root commit itself (standard git range behavior). In a repo with only one commit (root = HEAD), this produces an empty range, resulting in `type=none` (no release). The first release requires at least two commits. In practice this is not an issue since the root commit is typically a trivial initial commit.

**Applies to**: Any repo running the action for the first time (no existing production tags).

---

## Known Behaviors (Not Bugs)

### Reverted commits still appear in changelogs

**Scenario**: Feature work is merged to staging, then reverted (e.g., production rollback). The revert undoes the code changes but the original commits remain in git history.

**Impact**: The changelog shows ALL commits in the range (original + revert), making it appear larger than the actual diff. For example, one project showed 41 commits in `v2.2.0-rc.1` when only 5 files actually changed.

**Why**: `git log A..B` lists all commits between A and B, regardless of whether their changes were subsequently reverted. This is standard git behavior.

**Possible improvements**:
- Filter out commits whose changes are fully reverted (complex to implement reliably)
- Show a "net diff" summary alongside the commit list
- Add a `--no-merges` filter to reduce noise from merge commits (partially done)
- Collapse "Revert" commits with their originals

---

### Orphaned tags from reverted merges

**Scenario**: Staging is merged to master (creating tag `v2.1.1`), then the merge is reverted on master. The `v2.1.1` tag remains pointing to the now-reverted merge commit.

**Impact**: These tags are technically valid but point to code that was never actually released to production. They don't break the action but clutter the tag history.

**Current handling**: The RC cleanup step deletes RC pre-releases with versions <= current. Production tags are not deleted.

**Possible improvements**:
- Add a manual cleanup command/workflow for orphaned production tags
- Document the recommended manual cleanup process

---

### `[skip ci]` commit prevents double-run but requires re-trigger

**Scenario**: The action commits a version bump with `[skip ci]`. If the subsequent step (create-release) fails, the version is already bumped but no RC tag exists. Re-running the workflow skips the `[skip ci]` commit, so you need to push a new commit to re-trigger.

**Impact**: After a failure, you need to push a new commit (e.g., `git commit --allow-empty -m "chore: re-trigger auto-version"`) to restart the workflow.

**Why this is safe**: The bump-version script checks if the current version already matches the expected version and skips the bump if so. The RC numbering also checks for existing RC tags. So re-runs are idempotent.

---

### Version file format is auto-detected by filename

**Constraint**: The action auto-detects the version file format based on the filename:
- `package.json`, `composer.json`, `*.json` → JSON (`jq`)
- `pyproject.toml`, `*.toml` → TOML (`grep` + `sed`)
- `VERSION`, `VERSION.txt` → plain text (`cat`)
- `Chart.yaml`, `*.yaml` → YAML (`grep` + `sed`)

Files with unrecognized names will cause the action to fail with an error.

### `jq` reformats JSON files on write

**Behavior**: When writing to JSON files, `jq` reformats the entire file with 2-space indentation. Version bump commits may show formatting changes alongside the version update.

**Impact**: Cosmetic only. Matches the formatting that `npm version` previously produced. If the JSON file already uses 2-space indentation (standard for `package.json`), the diff will only show the version line change.

---

### `git describe` may find unexpected tags

**Scenario**: If tags from unrelated branches are present in the repo history (e.g., old tags from before the action was adopted), `git describe` may pick them up.

**Impact**: The "last production tag" could be an old, pre-action tag, causing the changelog to include a very large range of commits.

**Mitigation**: The action only considers tags matching the `vX.Y.Z` pattern (excludes `-rc.*`). Tags with non-standard formats are ignored.

---

## Open Items / Future Work

### Not yet covered

1. **Monorepo support** — The action bumps a single version file. Projects with multiple packages or services need separate version management.

2. **Custom changelog templates** — The changelog format (Breaking, Features, Fixes, Maintenance, Other) is hardcoded. Some teams may want different categories or formats.

3. **Scoped conventional commits** — `feat(auth):` is recognized as `feat:` but the scope is not used for grouping in changelogs.

4. **Pre-release channels** — Only one staging branch is supported. Some workflows need `alpha`, `beta`, `rc` channels.

5. **Tag signing** — Tags are created unsigned. GPG/SSH signing could be added as an option.

6. **Dry-run mode** — No way to preview what the action would do without actually creating tags/releases.

7. **Helm Chart `appVersion` auto-creation** — If `appVersion` field is missing, the action should either add it or warn, rather than silently skipping.

8. **Changelog diff summary** — Show the actual file diff alongside the commit list, so users can see the real impact vs. commit noise (e.g., reverted commits).

9. **Orphaned tag cleanup** — Provide a utility or workflow to clean up production tags that point to reverted code.

10. ~~**Non-Node.js version files**~~ — Done. Supported via `version-utils.sh`: JSON, TOML, YAML, plain text.

