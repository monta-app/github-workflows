# Claude Code Notes

## Last Documentation Update
- **Date**: 2026-02-23
- **Latest SHA**: b65d4f5 (check for newer commits)
- **Changes**: Created `deploy-kotlin-v2.yml` workflow for repo-based Kotlin service deployments

## Recent Workflow Changes (2026-02-23)
1. **Kotlin V2 Deploy Workflow**: Created `deploy-kotlin-v2.yml` for repo-based deployments
   - Uses `component-deploy-v2.yml` for service repository-based deployment pattern
   - Includes all Kotlin-specific features: tests, Gradle, service profile updates, release tags, changelog
   - Added `helm-values-path`, `repository-name`, and `argocd-app-name` inputs for flexible repo configuration
   - Maintains compatibility with all existing Kotlin workflow features

## Previous Changes (2025-07-11)
1. **Release Tag Prefix**: Added `release-tag-prefix` input to `deploy-kotlin.yml` for creating prefixed release tags (e.g., 'service-2024-01-15-14-30')
2. **Documentation**: Updated workflow guide with prefix parameter and usage example

## Previous Changes (2025-07-10)
1. **Changelog Pattern Filtering**: Added `changelog-tag-pattern` and `changelog-path-exclude-pattern` inputs to `deploy-kotlin.yml` for filtering changelog generation in monorepos
2. **Documentation**: Updated workflow guide with new changelog pattern parameters and examples

## Previous Changes (2025-06-29)
1. **Docker Compose Composite Action**: Created `.github/actions/docker-compose-setup` for reusable Docker Compose setup
2. **Workflow Updates**: Integrated Docker Compose action in `pull-request-bun.yml`, `component-test-python.yml`, and `deploy-python.yml`
3. **Documentation**: Updated workflow guide to document Docker Compose support

## Previous Changes (2025-06-21)
1. **Code Coverage**: Added LCOV coverage reporting to pull-request-bun workflow
2. **Docker Compose**: Added optional Docker Compose support for test services
3. **System Fixes**: Resolved man-db interactive prompts with debconf configuration
4. **Package Installation**: Added `-y` flags to apt install commands

When updating documentation next time, check commits since SHA: 6a249ca
