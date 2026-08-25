# hiddify-app — build & release helpers (gh + git)
#
# `repo` defaults to the ShuttleSpace fork where CI runs. Override per-invocation:
#     just repo=owner/name draft
repo := "ShuttleSpace/hiddify-app"

# Git remote to push release tags to (`origin` already points to the fork here).
# Override with: just remote=NAME tag 1.2.3
remote := "origin"

# List all commands
default:
    @just --list

# ---------------------------------------------------------------------------
# CI / build triggers (workflow_dispatch)
# ---------------------------------------------------------------------------

# Trigger a manual build and publish a draft prerelease
draft version="draft":
    gh workflow run manual-build.yml -R {{repo}} -f version={{version}} -f publish-prerelease=true

# Trigger a manual build (compile + upload artifacts, no release)
build version="draft":
    gh workflow run manual-build.yml -R {{repo}} -f version={{version}} -f publish-prerelease=false

# Trigger the CI workflow on a branch (dev by default)
ci branch="dev":
    gh workflow run ci.yml -R {{repo}} --ref {{branch}}

# ---------------------------------------------------------------------------
# Release / publish
# ---------------------------------------------------------------------------

# Create + push a release tag (triggers the Release workflow which builds & publishes)
tag version:
    git tag v{{version}}
    git push {{remote}} v{{version}}

# Full release: bump version files, commit, tag and push (wraps .github/change_version.sh)
release version:
    @echo "Releasing v{{version}} ..."
    @CORE_VERSION="$$(sed -n 's/^core\.version=//p' dependencies.properties)" GIT_REMOTE={{remote}} bash -c 'echo "{{version}}" | bash .github/change_version.sh'

# Create a GitHub release (generated notes) for an existing tag, without rebuilding
gh-release version:
    gh release create v{{version}} -R {{repo}} --generate-notes

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

# Watch the latest workflow run until it finishes
watch:
    gh run watch -R {{repo}}

# List recent workflow runs
runs:
    gh run list -R {{repo}} --limit 15
