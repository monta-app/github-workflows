# GitHub Workflows v3 Migration Guide

## Overview

This guide documents the migration from v2 to v3 of the GitHub deployment workflows, which introduces multi-architecture
support and improved workflow composition.

## Key Changes

### 1. Workflow File Updates

#### Deploy Workflows (dev, staging, production)

**Before (v2):**

```yaml
uses: monta-app/github-workflows/.github/workflows/deploy.yaml@v2
with:
  service-name: "Integrations Service"
  service-emoji: "🫶"
  service-identifier: integrations
  region: eu-west-1
  stage: dev
  upload-open-api: true
  more-power: true
  java-version: 21
```

**After (v3):**

```yaml
uses: monta-app/github-workflows/.github/workflows/deploy-kotlin.yaml@v3
with:
  runner-size: "normal"
  stage: dev
  service-name: "Integrations Service"
  service-emoji: "🫶"
  service-identifier: integrations
```

**What changed:**

- Workflow path changed from `deploy.yaml` to `deploy-kotlin.yaml`
- Version updated from `@v2` to `@v3`
- Removed explicit parameters that are now defaults:
    - `region: eu-west-1`
    - `upload-open-api: true`
    - `more-power: true`
    - `java-version: 21`
- `stage` parameter moved to the top for clarity
- `runner-size` now determines your runner size (can be normal or large please decide whats best for your project but
  don't just default to large if you don't need it :D)

#### Pull Request Workflow

**Before (v2):**

```yaml
uses: monta-app/github-workflows/.github/workflows/pull-request-kover.yaml@v2
with:
  action-runner: linux-x64-xl
  java-version: 21
```

**After (v3):**

```yaml
uses: monta-app/github-workflows/.github/workflows/pull-request-kotlin.yaml@v3
with:
  runner-size: "normal"
  java-version: 21 // Default is java 21 (leave out if you don't need it)
```

**What changed:**

- Workflow renamed from `pull-request-kover.yaml` to `pull-request-kotlin.yaml`
- `action-runner` parameter replaced with `runner-size`
- Java version no longer needs to be specified (handled by the workflow)

### 2. Dockerfile Improvements

#### Build Stage Optimization

**Before:**

```dockerfile
ARG GHL_USERNAME=NA
ARG GHL_PASSWORD=NA
ENV GHL_USERNAME ${GHL_USERNAME}
ENV GHL_PASSWORD ${GHL_PASSWORD}
RUN ./gradlew --no-daemon clean buildLayers
```

**After:**

```dockerfile
RUN --mount=type=cache,target=/root/.gradle \
    --mount=type=secret,id=GHL_USERNAME \
    --mount=type=secret,id=GHL_PASSWORD \
    GHL_USERNAME=$(cat /run/secrets/GHL_USERNAME 2>/dev/null || echo "NA") \
    GHL_PASSWORD=$(cat /run/secrets/GHL_PASSWORD 2>/dev/null || echo "NA") \
    ./gradlew --no-daemon clean buildLayers
```

**What changed:**

- Implements Docker BuildKit cache mounting for Gradle dependencies
- Uses secret mounting instead of build args for better security
- Credentials are read from mounted secrets at build time

#### ENTRYPOINT Format

**Before:**

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

**After:**

```dockerfile
ENTRYPOINT ["java", "-server", "-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseContainerSupport", "-XX:InitialRAMPercentage=50", "-XX:MaxRAMPercentage=75", "-XX:+UseStringDeduplication", "-jar", "/home/app/application.jar"]
```

**What changed:**

- Changed to exec form (JSON array) for better signal handling
- Improves container shutdown behavior

## Benefits of v3 Migration

1. **Multi-Architecture Support**: v3 workflows support building for multiple architectures (e.g., AMD64, ARM64)
2. **Improved Build Performance**: Docker BuildKit cache mounting significantly speeds up builds
3. **Better Security**: Secrets are handled more securely using Docker secret mounts
4. **Simplified Configuration**: Many defaults are now built into the workflows, reducing configuration overhead
5. **Better Resource Management**: New runner size configuration provides more flexibility

## Migration Steps

1. Update all deployment workflow files to use `deploy-kotlin.yaml@v3`
2. Update pull request workflow to use `pull-request-kotlin.yaml@v3`
3. Remove unnecessary parameters that are now defaults
4. Update Dockerfile to use BuildKit features for better caching and security
5. Test the workflows in your dev environment first

## Additional Considerations

- The v3 workflows assume sensible defaults for Kotlin/Java services
- Region defaults to `eu-west-1`
- Java version defaults to 21
- OpenAPI upload is enabled by default
- Normal runners are used by default (can be configured with `runner-size` parameter)
