# Edge Cases & Findings

Lessons learned from real-world usage, initially discovered during the DLMS project integration. This document captures bugs found and fixed, known behaviors, and open items that may need future work.

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

**Lesson**: Never "fix" indentation inside `run: |` blocks — YAML handles it correctly. This was initially identified as a bug in the original DLMS workflow but turned out to be a non-issue.

---

### 6. Heredoc quoting prevents variable expansion

**Context**: In the original DLMS workflow, production release notes used `<< 'EOF'` (quoted heredoc), which prevents `$VARIABLE` expansion. The workaround was fragile sed/awk substitution after the fact.

**Fix**: The extracted action uses `printf` statements instead of heredocs, avoiding this class of issues entirely. Each line is explicitly formatted with variables as arguments.

---

## Known Behaviors (Not Bugs)

### Reverted commits still appear in changelogs

**Scenario**: Feature work is merged to staging, then reverted (e.g., production rollback). The revert undoes the code changes but the original commits remain in git history.

**Impact**: The changelog shows ALL commits in the range (original + revert), making it appear larger than the actual diff. For example, DLMS showed 41 commits in `v2.2.0-rc.1` when only 5 files actually changed.

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

### Version file must use `"version": "x.y.z"` format

**Constraint**: The action reads the version using `node -pe "require('./package.json').version"`. This requires:
- A valid JSON file with a `version` field
- Node.js installed in the runner
- The file path relative to the workspace root

Other version file formats (e.g., Python `setup.py`, Gradle `build.gradle`) are not supported.

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

10. **Non-Node.js version files** — Support reading version from `setup.py`, `build.gradle`, `Cargo.toml`, etc.

---

## Real-World Reference: DLMS

The DLMS project (`web/dlms`) was the first consumer of this action. Key details:

- **Version file**: `js-app/package.json`
- **Helm chart**: `helm/dlms/Chart.yaml`
- **GitHub Enterprise**: `git.epo.org` with API at `https://git.epo.org/api/v3`
- **Branches**: `staging` (RC) / `master` (production)
- **Runner**: `web-default` (self-hosted)

### DLMS-specific findings

- The `appVersion` field was missing from Chart.yaml and had to be added manually before the action could update it.
- After a production rollback (revert of staging→master merge), staging retained the original code while master was reverted. The action handled this correctly — the next staging push re-used the already-bumped version and created a new RC.
- Old tags from pre-action workflow runs (e.g., `v2.2.0` pointing to an old merge commit) caused the changelog to use a wrong baseline. Fixed by switching from global tag sort to ancestor-based `git describe`.
- The workflow was reduced from ~745 lines of inline shell to 45 lines referencing `web/auto-version-action@v1`.
