# Claude Code Notes

## Last Documentation Update
- **Date**: 2026-08-28
- **Latest SHA**: b076da4 (check for newer commits)
- **Changes**: Added opt-in `resource-name`/`resource-kind`/`resource-namespace` inputs to `argocd-wait-sync`

## Recent Changes (2026-08-28)
1. **`argocd-wait-sync` resource-level tracking**: Added opt-in `resource-name` (+ `resource-kind`, default `Deployment`, and `resource-namespace`) inputs to `.github/actions/argocd-wait-sync`. When `resource-name` is set, completion and fail-fast (Degraded/Missing) are judged on that specific resource in `.status.resources[]` instead of the app's aggregate `.status.health`, so an app that manages multiple independently-owned resources (e.g. a shared/monorepo-style app with several Deployments) won't falsely pass before your resource rolls out, or block forever because an unrelated resource in the same app is Degraded/Progressing. Empty `resource-name` (default) is fully backwards compatible - identical behavior to before. `wait-sync.sh` gains a `TARGET_HEALTHY` variable that is the single source of truth for "is the thing we care about healthy" (the tracked resource when set, otherwise app aggregate health), used by both phases of the state machine. `test-local.sh` gains matching `--resource-name`/`--resource-kind`/`--resource-namespace` flags.

## Previous Changes (2026-08-26)
1. **`argocd-wait-sync-multi` action**: New composite action at `.github/actions/argocd-wait-sync-multi` that waits concurrently for MANY ArgoCD apps to sync and become healthy at an expected revision, fails fast on any Degraded/Missing/failed/diverged/timeout, and emits one aggregated `deployments` JSON (per-app `start`/`end`/`revision`/`status`/`url`). Sibling of `argocd-wait-sync` (left untouched); reuses the same per-app state machine, fail-fast conditions and supersede-via-ancestry check. Adds a `source-repo` input to verify **multi-source** apps against `.status.sync.revisions[<source index>]` (the singular `.status.sync.revision` is empty on multi-source apps). Built for monorepo-style repos that bump many services in one manifests commit. Offline tests: `.github/actions/argocd-wait-sync-multi/test/run-tests.sh`.

## Recent Workflow Changes (2026-08-06)
1. **Changelog Release Notifications**: Added `changelog-monitoring-urls` and `changelog-release-notify-channel` inputs to `deploy-kotlin.yml` and `deploy-kotlin-v2.yml`, forwarded to the `changelog-cli-action`'s `monitoring-urls`/`release-notify-channel` inputs. Posts a standalone Slack message with the release link, dashboards to monitor, and tagged PR authors/co-authors/approvers - independent of `enable-changelog`/`output`, reuses the existing `SLACK_APP_TOKEN` secret.

## Previous Changes (2026-06-17)
1. **ARM64-only image builds**: Purged all x86/amd64 support from the build and CI surface
   - `component-build.yml`: removed the amd64+arm64 build matrix and the `create-manifest` job. Now does a single native ARM64 build (`platforms: linux/arm64`) that pushes the `<sha>` and `latest` tags directly, with no per-arch suffixes and no multi-arch manifest list. The setup job resolves a single arm64 runner and the buildcache is no longer per-arch scoped.
   - `runner-size-converter` action: dropped the `architecture` input; always emits `linux-arm64` / `linux-arm64-xl`.
   - `architecture` input: stopped forwarding it anywhere (it no longer selects a runner). Removed entirely from the internal/analysis workflows (`code-coverage-kotlin`, `component-test-kotlin`, `component-test-python`). On the entry-point workflows service repos call directly (`pull-request-{kotlin,bun,react}`, `sonar-cloud`, `deploy-{kotlin,kotlin-v2,python,generic,generic-v2}`) it is RETAINED as a deprecated no-op: the value is ignored, the description marks it deprecated, and `deploy-kotlin-v2` gains it for v1/v2 parity. Slated for removal in a future release.
   - `actionlint.yaml`: removed the `linux-x64`, `linux-x64-xl`, `self-hosted-x64`, `self-hosted-x64-2xl` labels.
   - **Breaking for callers**: only repos calling the internal workflows (`code-coverage-kotlin`, `component-test-kotlin`, `component-test-python`) directly with `architecture:` must drop that input. Callers of the deploy / pull-request / sonar-cloud entry points are unaffected (the input is accepted and ignored).
2. **Optional Blacksmith cloud runners**: added a `use-blacksmith-runners` input (type boolean, default false) to every workflow that exposes `runner-size`, threaded through to `runner-size-converter`. When true the converter resolves Blacksmith arm64 cloud runners (`blacksmith-4vcpu-ubuntu-2404-arm` for normal, `blacksmith-16vcpu-ubuntu-2404-arm` for large); when false it keeps resolving the self-hosted `linux-arm64` / `linux-arm64-xl` runners.
   - `component-build.yml` now has two separate, mutually exclusive build jobs gated on the flag: `build-blacksmith` uses `useblacksmith/setup-docker-builder` + `useblacksmith/build-push-action` with sticky-disk layer cache, while `build-self-hosted` uses `docker/setup-buildx-action` + `docker/build-push-action` with the registry-backed ECR buildcache. A shared `setup` job resolves the runner and the image tag. The old `enable-buildkit-cache` toggle was dropped.
   - Added the `blacksmith-4vcpu-ubuntu-2404-arm` and `blacksmith-16vcpu-ubuntu-2404-arm` labels to `actionlint.yaml`; documented the input in the converter README and workflow guide.
   - Backwards compatible: callers that do not set the input keep using the self-hosted runners.

## Previous Changes (2026-02-23)
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
