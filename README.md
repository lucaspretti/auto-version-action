# Auto Version Action

A reusable GitHub Action for **automated semantic versioning** driven by [Conventional Commits](https://www.conventionalcommits.org/). Designed for workflows with a staging branch (RC tags) and a production branch (final releases).

## Features

- **Conventional commit analysis** — `feat:`, `fix:`, `chore:`, `<type>!:`, `BREAKING CHANGE` ([spec](https://www.conventionalcommits.org/en/v1.0.0/))
- **Semver bump calculation** from last production tag
- **RC tag creation** with sequential numbering (`v1.2.0-rc.1`, `v1.2.0-rc.2`, ...)
- **Version escalation** — higher-priority bumps reset RC numbering
- **Categorized changelogs** — Breaking, Features, Fixes, Maintenance, Other
- **RC cleanup** on production release (including orphaned RCs from escalation)
- **Branch sync** — production merged back to staging automatically
- **GitHub Enterprise Server** support via `github-api-url` input

## Quick Start

> **Prerequisites:** Your repository must have a version file (`package.json`, `composer.json`, `pyproject.toml`, `VERSION`, or `Chart.yaml`) with a version field, and commits should follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, etc.). The file format is auto-detected by filename.

### Minimal setup (single branch, production only)

```yaml
name: Auto Version

on:
  push:
    branches: [master]

jobs:
  version:
    runs-on: ubuntu-latest
    if: >-
      ${{ !contains(github.event.head_commit.message, '[skip ci]') &&
          !contains(github.event.head_commit.message, '[ci skip]') }}
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0    # Required: full history for commit analysis

      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Full setup (staging + production with RC releases)

```yaml
name: Auto Version

on:
  push:
    branches: [master, staging]

jobs:
  version:
    runs-on: ubuntu-latest
    if: >-
      ${{ !contains(github.event.head_commit.message, '[skip ci]') &&
          !contains(github.event.head_commit.message, '[ci skip]') }}
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: Auto Version
        id: version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # Use outputs in subsequent steps
      - name: Print version info
        run: |
          echo "Version: ${{ steps.version.outputs.version }}"
          echo "Bump type: ${{ steps.version.outputs.bump-type }}"
          echo "RC version: ${{ steps.version.outputs.rc-version }}"
          echo "Changed: ${{ steps.version.outputs.version-changed }}"
```

### GitHub Enterprise Server

For GHES instances, add `github-api-url` to ensure API calls reach the correct endpoint:

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          github-api-url: ${{ github.api_url }}
```

> **Note for GHES:** Replace `runs-on: ubuntu-latest` with your self-hosted runner label (e.g., `runs-on: self-hosted`). Use `${{ github.api_url }}` instead of hardcoding the API URL so it works automatically on any instance.

### Protected branches (GitHub App token)

If the production or staging branch has branch protection that requires pull requests, the
default `GITHUB_TOKEN` (acting as `github-actions[bot]`) cannot push the bump commit and the
action fails with `GH006 Protected branch update failed`.

The recommended solution is to run the action as a GitHub App that is included in the branch
protection `bypass_pull_request_allowances` list. Mint an installation token before calling the
action and pass it as both the checkout token and the `github-token` input:

```yaml
    steps:
      - name: Generate App Token
        id: app-token
        uses: actions/create-github-app-token@v2
        with:
          app-id: ${{ vars.AUTO_VERSION_APP_ID }}
          private-key: ${{ secrets.AUTO_VERSION_APP_KEY }}
          github-api-url: ${{ github.api_url }}

      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
          token: ${{ steps.app-token.outputs.token }}
          persist-credentials: true

      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ steps.app-token.outputs.token }}
          github-api-url: ${{ github.api_url }}
```

Requirements:
- A GitHub App installed on the repository with `contents: write` permission.
- The app's ID stored as a repo/org variable (not sensitive).
- The app's private key stored as a repo/org secret.
- The app added to the branch protection bypass list for the production/staging branches.

The same pattern unblocks any automated commit from a workflow (data refresh bots, Renovate,
etc.) against a protected branch. Humans still go through pull requests; only the app identity
is allowed to push directly.

#### Alternative: Personal Access Token (PAT)

For small/personal repositories on github.com where creating a dedicated GitHub App is
overkill, a Personal Access Token is simpler:

```yaml
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
          token: ${{ secrets.RELEASE_PAT }}
          persist-credentials: true

      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.RELEASE_PAT }}
```

Requirements:
- A classic or fine-grained PAT with `contents: write` permission (and `workflows: write` if
  the action ever edits workflow files).
- Added to the branch protection bypass list as a user (or the PAT's user is on the allow list).

Trade-offs vs. GitHub App:
- Simpler setup (no app registration or installation).
- PAT is tied to a user account — if that user leaves, the PAT dies.
- PAT expires and must be rotated; App installation tokens are minted fresh per run.
- For machine identity, a dedicated "machine user" account holding the PAT is often preferred.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `version-file` | **yes** | — | Path to version file (`package.json`, `composer.json`, `pyproject.toml`, `VERSION`, `Chart.yaml`). Auto-detected by filename. |
| `helm-chart` | no | `""` | Path to `Chart.yaml` to update `appVersion` |
| `staging-branch` | no | `staging` | Name of the staging/RC branch |
| `production-branch` | no | `master` | Name of the production branch |
| `github-token` | **yes** | — | Token for creating releases and tags |
| `github-api-url` | no | `https://api.github.com` | API URL for GitHub Enterprise Server |
| `update-floating-tags` | no | `"false"` | Update `vMAJOR` and `vMAJOR.MINOR` floating tags on production release |
| `deployment-info` | no | `""` | Markdown block for deployment section in release notes |

## Outputs

| Output | Description |
|---|---|
| `version` | Base version (e.g., `2.1.1`) |
| `rc-version` | Full RC version if staging (e.g., `2.1.1-rc.3`) |
| `rc-number` | RC number (e.g., `3`) |
| `bump-type` | `major`, `minor`, `patch`, or `none` |
| `version-changed` | `true` if version was bumped |

## How It Works

### Version Flow

```
Commit to staging -> Analyze commits -> Bump version -> Create RC tag -> Pre-release
Merge to master  -> Read version    -> Create tag    -> Release       -> Cleanup RCs
```

### Commit Convention

Follows the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. Automated commits containing `[skip ci]` are filtered out before analysis to prevent phantom version bumps.

| Commit prefix | Bump type | Example |
|---|---|---|
| `<type>!:` or `BREAKING CHANGE` | **major** | `feat!: redesign API`, `fix!: change auth flow` |
| `feat:` | **minor** | `feat: add search filter` |
| `fix:`, `chore:`, `docs:`, etc. | **patch** | `fix: resolve null pointer` |

The `!` modifier works on **any** commit type (`feat!:`, `fix!:`, `chore!:`, `refactor!:`, etc.) to signal a breaking change, per the spec.

Commit types are also detected when preceded by an issue reference (e.g., `#123 feat: add feature` or `web/repo#42 fix: resolve bug`).

### Intelligent Version Escalation

The action analyzes **all commits since the last production release** to determine the highest-priority bump:

```
Production: v1.0.0
fix: bug A         -> v1.0.1-rc.1  (patch)
fix: bug B         -> v1.0.1-rc.2  (same priority, increment RC)
feat: new feature  -> v1.1.0-rc.1  (higher priority, re-bump + reset RC)
fix: bug C         -> v1.1.0-rc.2  (lower priority, increment RC)
feat!: breaking    -> v2.0.0-rc.1  (highest priority, re-bump + reset RC)
```

### Staging Behavior

1. Analyze all commits since last production tag
2. Determine bump type (major > minor > patch)
3. If RC tags exist: compare priority, re-bump if higher
4. Update version file (and optional `Chart.yaml`)
5. Commit with `[skip ci]`, create RC tag, create GitHub Pre-release

### Production Behavior

The production branch **never bumps the version or pushes commits** in two-branch mode. The
correct version arrives via the staging merge. This avoids issues with protected branches and
race conditions when staging auto-version has not yet completed.

**Two-branch mode** (staging branch exists on remote):

1. Read the current version from the version file (set by the staging merge)
2. If a release tag (`v{version}`) already exists, skip (already released)
3. If RC tags exist for this version, proceed: output `version_changed=false`, let
   `create-release.sh` create the production tag and release
4. If no RC tags and the merge came from staging, skip (staging cycle incomplete,
   auto-version has not run yet)
5. If no RC tags and the merge did NOT come from staging (hotfix), use the version
   from the version file as-is (no bump, no push)

**Single-branch mode** (no staging branch on remote):

1. Analyze commits and calculate the expected version (same as old behavior)
2. If the current version is already correct, use it
3. If outdated, bump the version file, commit, and push

After `bump-version.sh`, subsequent steps handle tag creation, release notes, RC cleanup,
and branch sync.

**Production behavior by scenario:**

| Scenario | Staging exists? | RC tags? | Merge from staging? | Result |
|---|---|---|---|---|
| Normal release | yes | yes | yes | Read version, create release (no bump) |
| Normal release (hotfix) | yes | no | no | Read version, create release (no bump) |
| Staging merge before RC cycle | yes | no | yes | Skip (staging cycle incomplete) |
| Already released | yes | n/a | n/a | Skip (tag exists) |
| Single-branch mode | no | n/a | n/a | Bump + release (full flow) |

## Workflow Modes

### Two-branch (staging + production)

The recommended flow for applications with pre-production environments. Commits go to staging first, creating RC pre-releases, then merge to production for the final release.

```yaml
on:
  push:
    branches: [master, staging]
```

### Single-branch (production only)

For simpler projects that don't need RC releases. Push directly to the production branch — the action analyzes commits, bumps the version, and creates the release in one step.

```yaml
on:
  push:
    branches: [master]
```

Both modes use the same action configuration. The difference is only which branches trigger the workflow.

## Supported Ecosystems

The action auto-detects the version file format by filename and uses `jq`/`sed` for reading and writing. No Node.js required.

| Ecosystem | Version file | Read | Write |
|---|---|---|---|
| Node.js / Next.js / React | `package.json` | `jq -r '.version'` | `jq '.version = "X"'` |
| PHP / Drupal | `composer.json` | `jq -r '.version'` | `jq '.version = "X"'` |
| Python | `pyproject.toml` | `grep` + `sed` | `sed -i` |
| Plain / Shell | `VERSION` or `VERSION.txt` | `cat` | `echo > file` |
| YAML / Helm | `Chart.yaml` / `*.yaml` | `grep` + `sed` | `sed -i` |
| Helm Charts (appVersion) | `Chart.yaml` via `helm-chart` input | — | `sed -i` |

## Examples

### With Helm Chart

Updates `appVersion` in your Helm `Chart.yaml` alongside the version file:

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: js-app/package.json
          helm-chart: helm/my-app/Chart.yaml
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Custom Branch Names

Use `develop`/`main` instead of the default `staging`/`master`:

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          staging-branch: develop
          production-branch: main
```

### PHP / Drupal (composer.json)

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: composer.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Python (pyproject.toml)

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: pyproject.toml
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Plain VERSION file

For repos without a package manager (shell scripts, documentation, etc.):

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: VERSION
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Custom Deployment Info in Release Notes

Add environment details to the release notes:

```yaml
      - name: Auto Version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          deployment-info: |
            - **Environment**: ${{ github.ref_name == 'master' && 'Production' || 'Staging' }}
            - **Cluster**: `my-k8s-cluster`
```

### Using Outputs for Docker Build

Use the version output to tag Docker images:

```yaml
      - name: Auto Version
        id: version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          github-api-url: ${{ github.api_url }}

      - name: Build and push Docker image
        if: steps.version.outputs.version-changed == 'true'
        run: |
          docker build -t my-registry/my-app:${{ steps.version.outputs.version }} .
          docker push my-registry/my-app:${{ steps.version.outputs.version }}
```

### Conditional Deployment

Only deploy when the version actually changed:

```yaml
      - name: Auto Version
        id: version
        uses: lucaspretti/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
          github-api-url: ${{ github.api_url }}

      - name: Deploy to staging
        if: >-
          steps.version.outputs.version-changed == 'true' &&
          github.ref_name == 'staging'
        run: |
          echo "Deploying RC ${{ steps.version.outputs.rc-version }}..."
          # your deploy script here

      - name: Deploy to production
        if: github.ref_name == 'master'
        run: |
          echo "Deploying v${{ steps.version.outputs.version }}..."
          # your deploy script here
```

## Pinning Versions

This action uses **floating tags** so consumers always get the latest fixes:

| Reference | Resolves to | Use case |
|---|---|---|
| `@v1` | Latest `v1.x.x` release | Recommended — always up to date |
| `@v1.2` | Latest `v1.2.x` patch | Pin to a minor version |
| `@v1.2.3` | Exact version | Full reproducibility |

Floating tags (`v1`, `v1.2`) are updated automatically when `update-floating-tags: "true"` is set. This is useful for GitHub Actions consumed by other repos. Off by default.

## Architecture

```
auto-version-action/
├── action.yml              # Composite action definition
├── scripts/
│   ├── version-utils.sh    # Shared read/write version functions (auto-detects file format)
│   ├── analyze-commits.sh  # Commit analysis + bump type detection
│   ├── bump-version.sh     # Version bump + RC numbering logic
│   ├── create-release.sh   # Release/pre-release creation with changelog
│   ├── cleanup-rc.sh       # RC pre-release cleanup on production
│   ├── update-floating-tags.sh # Move vMAJOR/vMAJOR.MINOR tags (opt-in)
│   └── summary.sh          # GitHub Actions step summary
├── tests/
│   ├── run-all.sh          # Test runner
│   ├── test-helper.sh      # Minimal bash assertion framework
│   ├── test-analyze-commits.sh
│   ├── test-bump-version.sh
│   └── test-version-utils.sh
└── README.md
```

## Branch Protection Compatibility

When using branch protection on the production branch (e.g., requiring pull requests), the
action needs permission to push the version bump commit directly in **single-branch mode**.
Add the GitHub Actions app to the **"Allow specified actors to bypass required pull requests"**
list in branch protection settings.

In **two-branch mode**, the production flow never pushes commits (the version comes from the
staging merge), so branch protection is not an issue.

## Edge Cases & Known Behaviors

See [docs/edge-cases-and-findings.md](docs/edge-cases-and-findings.md) for:
- Bugs found and fixed during real-world usage
- Known behaviors (reverted commits in changelogs, orphaned tags, etc.)
- Open items and future work
- Reference implementation details from real-world integrations

## Requirements

- **jq** — used for JSON version files and release API calls
- **sed** — used for TOML/YAML version files
- **Git** — with full history (`fetch-depth: 0` on checkout)

## License

MIT
