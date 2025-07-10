# GitHub Workflows v3 Migration Guide

## Instructions for LLMs

This migration guide provides comprehensive instructions for updating GitHub workflows, Dockerfiles, and local development scripts from v2 to v3. When using this guide:

1. **Follow all sections systematically** - Each section contains required changes that must be implemented together
2. **Preserve existing configuration** - Only modify the specific elements outlined in each section
3. **Validate parameter formats** - Ensure all YAML parameters are properly quoted and ordered as specified
4. **Update secrets mapping** - Pay special attention to AWS secret name changes in the secrets configuration section
5. **Test after migration** - Use the validation checklist to verify all changes work correctly

This section is specifically designed for LLM assistance with migration tasks.

## Required Changes

### 1. GitHub Workflow Files

#### Deploy Workflows (dev, staging, production)

Replace:

```yaml
uses: monta-app/github-workflows/.github/workflows/deploy.yml@v2
```

With:

```yaml
uses: monta-app/github-workflows/.github/workflows/deploy-kotlin.yml@main
```

**Remove these parameters (now defaults):**

- `region: eu-west-1`
- `upload-open-api: true`
- `more-power: true`
- `java-version: 21`

**Parameter Updates:**

- Always wrap values in quotes: `stage: "production"`
- Always include `runner-size: "normal"` (or `"large"` if needed)
- Order parameters: `stage` first, then `runner-size`, then remaining parameters

**Secrets Configuration:**

Only pass these secrets to the workflow (use only the ones from your original deployment):

- `GHL_USERNAME`
- `GHL_PASSWORD` 
- `AWS_ACCOUNT_ID`
- `SLACK_APP_TOKEN`
- `MANIFEST_REPO_PAT`
- `SENTRY_AUTH_TOKEN`
- `AWS_CDN_ACCESS_KEY_ID`
- `AWS_CDN_SECRET_ACCESS_KEY`

**AWS Secret Migration:**
- `PRODUCTION_AWS_ACCESS_KEY_ID` → `AWS_ACCOUNT_ID: ${{ secrets.PRODUCTION_AWS_ACCOUNT_ID }}`
- `STAGING_AWS_ACCESS_KEY_ID` → `AWS_ACCOUNT_ID: ${{ secrets.STAGING_AWS_ACCOUNT_ID }}`
- Internal repos → `AWS_ACCOUNT_ID: ${{ secrets.INTERNAL_AWS_ACCOUNT_ID }}`

#### Pull Request Workflow

Replace:

```yaml
uses: monta-app/github-workflows/.github/workflows/pull-request-kover.yml@v2
```

With:

```yaml
uses: monta-app/github-workflows/.github/workflows/pull-request-kotlin.yml@main
```

**Replace parameter:**

- `action-runner: linux-x64-xl` → `runner-size: "normal"`

### 2. Dockerfile Updates

#### Add BuildKit Syntax Directive

Add this as the first line of your Dockerfile:

```dockerfile
# syntax=docker/dockerfile:1
```

#### Build Stage

Replace:

```dockerfile
ARG GHL_USERNAME=NA
ARG GHL_PASSWORD=NA
ENV GHL_USERNAME ${GHL_USERNAME}
ENV GHL_PASSWORD ${GHL_PASSWORD}
RUN ./gradlew --no-daemon clean buildLayers
```

With:

```dockerfile
RUN --mount=type=cache,target=/root/.gradle \
    --mount=type=secret,id=GHL_USERNAME,env=GHL_USERNAME \
    --mount=type=secret,id=GHL_PASSWORD,env=GHL_PASSWORD \
    ./gradlew --no-daemon clean buildLayers
```

**Note**: The `env=` syntax automatically makes the secret available as an environment variable during the RUN command, eliminating the need for manual secret reading.

#### ENTRYPOINT Format

Replace shell form:

```dockerfile
ENTRYPOINT java \
-server \
-XX:+UseG1GC \
-XX:+UnlockExperimentalVMOptions \
-XX:+UseContainerSupport \
-XX:InitialRAMPercentage=50 \
-XX:MaxRAMPercentage=75 \
-XX:+UseStringDeduplication \
-jar /home/app/application.jar
```

With exec form:

```dockerfile
ENTRYPOINT ["java", "-server", "-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseContainerSupport", "-XX:InitialRAMPercentage=50", "-XX:MaxRAMPercentage=75", "-XX:+UseStringDeduplication", "-jar", "/home/app/application.jar"]
```

### 3. Local Development Script (run_docker.sh)

Replace:

```bash
build() {
  docker build \
  --build-arg=GHL_USERNAME="$GHL_USERNAME" \
  --build-arg=GHL_PASSWORD="$GHL_PASSWORD" \
  -f Dockerfile \
  -t "$APP_NAME" ..
}
```

With:

```bash
build() {
  export GHL_USERNAME="${GHL_USERNAME:-$(getProperty "gpr.user")}"
  export GHL_PASSWORD="${GHL_PASSWORD:-$(getProperty "gpr.key")}"
  
  DOCKER_BUILDKIT=1 docker build \
  --secret id=GHL_USERNAME,env=GHL_USERNAME \
  --secret id=GHL_PASSWORD,env=GHL_PASSWORD \
  -f Dockerfile \
  -t "$APP_NAME" ..
}
```

### 4. Production Release Workflow

The `deploy-kotlin.yml` workflow now includes optional release tag creation and changelog generation features that are disabled by default. To enable these for production deployments:

```yaml
name: Deploy Production

on:
  push:
    tags:
      - '*'
  workflow_dispatch:

concurrency:
  group: 'deploy-production'
  cancel-in-progress: true

jobs:
  deploy:
    name: Deploy
    uses: monta-app/github-workflows/.github/workflows/deploy-kotlin.yml@main
    with:
      stage: "production"
      runner-size: "large"
      service-name: "Your Service Name"
      service-emoji: "🚀"
      service-identifier: "your-service"
      gradle-module: "app"
      enable-release-tag: true      # Enables automatic tag creation on workflow_dispatch
      enable-changelog: true        # Enables changelog generation after deployment
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      AWS_ACCOUNT_ID: ${{ secrets.PRODUCTION_AWS_ACCOUNT_ID }}
      MANIFEST_REPO_PAT: ${{ secrets.PAT }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

**Key features:**
- **Release Tag Creation**: When `enable-release-tag: true` and triggered via `workflow_dispatch`, automatically creates a release tag
- **Changelog Generation**: When `enable-changelog: true`, generates a changelog after successful deployment
  - Posts to `#releases` Slack channel
  - Creates GitHub release
  - Integrates with Jira (montaapp)
- Both features are **disabled by default** to maintain backward compatibility
- The workflow handles all conditional logic internally

## Why Migrate?

- **Faster builds** - BuildKit caching reduces build times
- **Better security** - Secrets not stored in image layers
- **Multi-architecture support** - ARM64 and AMD64 builds
- **Less configuration** - Sensible defaults built-in

## Validation Checklist

After migration:

- [ ] All GitHub workflows run successfully
- [ ] `docker history <image>` shows no credentials
- [ ] Local builds work with updated `run_docker.sh`
- [ ] Build times improved on subsequent builds
