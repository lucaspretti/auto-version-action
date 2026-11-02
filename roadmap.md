# Roadmap

## In Progress

### Test coverage for remaining scripts
- [x] `test-create-release.sh` - changelog categorization, skip-ci filtering, write_sections output
- [x] `test-cleanup-rc.sh` - RC version comparison, tag parsing
- [x] `test-bump-version-integration.sh` - single-branch production bump paths

## Planned

### CI workflow for automated testing
- [ ] `.github/workflows/tests.yml` - runs `bash tests/run-all.sh` on push/PR
- [ ] Runs on `ubuntu-latest` (tests are pure bash, no GHES needed)

### Commit parsing robustness
- [ ] Process commits individually instead of concatenating all subjects into one blob
- [ ] Reduces risk of cross-commit false positives

### Auto-update v1 floating tag
- [ ] Ensure v1 tag is always moved after release to avoid stale action code
- [ ] Currently relies on `update-floating-tags.sh` which only runs on successful release

### Integration tests
- [x] End-to-end test that creates a temp git repo, runs the pipeline, and verifies output
- [ ] Covers more scenarios: tag creation, commit ranges, two-branch mode
