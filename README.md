# Auto Version Action

A reusable GitHub Action for **automated semantic versioning** driven by [Conventional Commits](https://www.conventionalcommits.org/). Designed for workflows with a staging branch (RC tags) and a production branch (final releases).

## Features

- **Conventional commit analysis** — `feat:`, `fix:`, `chore:`, `feat!:`, `BREAKING CHANGE`
- **Semver bump calculation** from last production tag
- **RC tag creation** with sequential numbering (`v1.2.0-rc.1`, `v1.2.0-rc.2`, ...)
- **Version escalation** — higher-priority bumps reset RC numbering
- **Categorized changelogs** — Breaking, Features, Fixes, Maintenance, Other
- **RC cleanup** on production release (including orphaned RCs from escalation)
- **Branch sync** — production merged back to staging automatically
- **GitHub Enterprise Server** support via `github-api-url` input

## Quick Start

```yaml
name: Automated Versioning & Release

on:
  push:
    branches: [master, staging]

jobs:
  version-and-release:
    runs-on: ubuntu-latest
    if: >-
      ${{ !contains(github.event.head_commit.message, '[skip ci]') &&
          !contains(github.event.head_commit.message, '[ci skip]') }}
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Auto Version
        uses: web/auto-version-action@v1
        with:
          version-file: package.json
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `version-file` | **yes** | — | Path to `package.json` (currently only `package.json` is supported) |
| `helm-chart` | no | `""` | Path to `Chart.yaml` to update `appVersion` |
| `staging-branch` | no | `staging` | Name of the staging/RC branch |
| `production-branch` | no | `master` | Name of the production branch |
| `github-token` | **yes** | — | Token for creating releases and tags |
| `github-api-url` | no | `https://api.github.com` | API URL for GitHub Enterprise Server |
| `deployment-info` | no | `""` | Markdown block for deployment section in release notes |

## Outputs

| Output | Description |
|---|---|
| `version` | Base version (e.g., `2.1.1`) |
| `rc-version` | Full RC version if staging (e.g., `2.1.1-rc.3`) |
| `rc-number` | RC number (e.g., `3`) |
| `bump-type` | `major`, `minor`, or `patch` |
| `version-changed` | `true` if version was bumped |

## How It Works

### Version Flow

```
Commit to staging -> Analyze commits -> Bump version -> Create RC tag -> Pre-release
Merge to master  -> Read version    -> Create tag    -> Release       -> Cleanup RCs
```

### Commit Convention

| Commit prefix | Bump type | Example |
|---|---|---|
| `feat!:` or `BREAKING CHANGE` | **major** | `feat!: redesign API` |
| `feat:` | **minor** | `feat: add search filter` |
| `fix:`, `chore:`, `docs:`, etc. | **patch** | `fix: resolve null pointer` |

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
4. Update `package.json` (and optional `Chart.yaml`)
5. Commit with `[skip ci]`, create RC tag, create GitHub Pre-release

### Production Behavior

1. Read version — if already correct (from staging), use it; otherwise bump automatically
2. Create production tag (`v1.2.0`)
3. Create GitHub Release with categorized changelog
4. Delete all RC pre-releases with version <= current
5. Sync production branch back to staging

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

The action uses `npm version` internally to bump the version file. Currently supported:

| Ecosystem | Supported | Version file |
|---|---|---|
| Node.js / Next.js / React | Yes | `package.json` |
| Helm Charts | Yes (appVersion only) | `Chart.yaml` via `helm-chart` input |
| Python | Not yet | `pyproject.toml` |
| PHP / Drupal | Not yet | `composer.json` |
| Go | Not yet | — |

## Advanced Usage

### With Helm Chart

```yaml
- uses: web/auto-version-action@v1
  with:
    version-file: js-app/package.json
    helm-chart: helm/my-app/Chart.yaml
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### GitHub Enterprise Server

```yaml
- uses: web/auto-version-action@v1
  with:
    version-file: js-app/package.json
    github-token: ${{ secrets.GITHUB_TOKEN }}
    github-api-url: https://git.epo.org/api/v3
```

### Custom Deployment Info in Release Notes

```yaml
- uses: web/auto-version-action@v1
  with:
    version-file: package.json
    github-token: ${{ secrets.GITHUB_TOKEN }}
    deployment-info: |
      - **Environment**: ${{ github.ref_name == 'master' && 'Production' || 'Staging' }}
      - **Cluster**: `my-k8s-cluster`
```

### Custom Branch Names

```yaml
- uses: web/auto-version-action@v1
  with:
    version-file: package.json
    github-token: ${{ secrets.GITHUB_TOKEN }}
    staging-branch: develop
    production-branch: main
```

## Architecture

```
auto-version-action/
├── action.yml              # Composite action definition
├── scripts/
│   ├── analyze-commits.sh  # Commit analysis + bump type detection
│   ├── bump-version.sh     # Version bump + RC numbering logic
│   ├── create-release.sh   # Release/pre-release creation with changelog
│   ├── cleanup-rc.sh       # RC pre-release cleanup on production
│   └── summary.sh          # GitHub Actions step summary
└── README.md
```

## Edge Cases & Known Behaviors

See [docs/edge-cases-and-findings.md](docs/edge-cases-and-findings.md) for:
- Bugs found and fixed during real-world usage
- Known behaviors (reverted commits in changelogs, orphaned tags, etc.)
- Open items and future work
- Reference implementation details from the DLMS project

## Requirements

- **Node.js** — used to read/write `package.json` version
- **jq** — used for JSON processing in release API calls
- **Git** — with full history (`fetch-depth: 0` on checkout)

## License

Internal EPO use.
