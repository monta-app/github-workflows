# GitHub Workflows Documentation Guide

This guide provides a comprehensive overview of all reusable GitHub workflows in this repository. Each workflow is designed to be called from your repository's workflows to standardize CI/CD processes across projects.

## Table of Contents

1. [Allow Deploys](#allow-deploys)
2. [Block Deploys](#block-deploys)
3. [Code Coverage (Kotlin)](#code-coverage-kotlin)
4. [Component Build](#component-build)
5. [Component Deploy](#component-deploy)
6. [Component Initialize](#component-initialize)
7. [Component Test (Kotlin)](#component-test-kotlin)
8. [Deploy Kotlin](#deploy-kotlin)
9. [Publish Tech Docs](#publish-tech-docs)
10. [Pull Request Kotlin](#pull-request-kotlin)
11. [Pull Request React (Bun)](#pull-request-react-bun)
12. [Pull Request React (pnpm)](#pull-request-react-pnpm)
13. [Rollback](#rollback)
14. [SonarCloud Analysis](#sonarcloud-analysis)
15. [Track Pending Release](#track-pending-release)

---

## Allow Deploys

**File:** `allow-deploys.yml`  
**Purpose:** Enables a specified workflow to allow deployments to proceed.

### What it does:
1. Enables the specified workflow using GitHub CLI
2. Useful for re-enabling deployment workflows after they've been blocked

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow` | Yes | - | Workflow (filename or name) to allow, e.g. "deploy-production.yml" |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `ADMIN_PAT` | Yes | GitHub PAT with workflow permissions |

### Example Usage:
```yaml
jobs:
  allow-deploys:
    uses: monta-app/github-workflows/.github/workflows/allow-deploys.yml@main
    with:
      workflow: "deploy-production.yml"
    secrets:
      ADMIN_PAT: ${{ secrets.PAT }}
```

---

## Block Deploys

**File:** `block-deploys.yml`  
**Purpose:** Disables a specified workflow and cancels any in-progress jobs to prevent deployments.

### What it does:
1. Disables the specified workflow using GitHub CLI
2. Waits for any in-progress jobs to start
3. Cancels all in-progress jobs for the specified workflow
4. Useful for preventing deployments during incidents or maintenance

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow` | Yes | - | Workflow (filename or name) to block, e.g. "deploy-production.yml" |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `ADMIN_PAT` | Yes | GitHub PAT with workflow permissions |

### Example Usage:
```yaml
jobs:
  block-deploys:
    uses: monta-app/github-workflows/.github/workflows/block-deploys.yml@main
    with:
      workflow: "deploy-production.yml"
    secrets:
      ADMIN_PAT: ${{ secrets.PAT }}
```

---

## Code Coverage (Kotlin)

**File:** `code-coverage-kotlin.yml`  
**Purpose:** Runs tests with code coverage reporting for Kotlin projects and pushes metrics to Prometheus.

### What it does:
1. Validates service name format (must be kebab-case)
2. Connects to Tailscale VPN
3. Sets up Java environment
4. Runs tests with Kover coverage reporting
5. Counts lines of code with `cloc`
6. Pushes coverage metrics to Prometheus

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service-name` | Yes | - | Project name in kebab-case format (e.g., "my-service") |
| `runner-size` | No | "normal" | Runner size: "normal" or "large" |
| `java-version` | No | "21" | Java version to use |
| `gradle-module` | No | - | Gradle module name for multi-module projects |
| `kover-report-path` | No | "build/reports/kover/report.xml" | Path to Kover XML report |
| `catalog-info-path` | No | "catalog-info.yaml" | Path to Backstage catalog file |
| `cloc-source-path` | No | "." | Path to analyze for lines of code |
| `cloc-exclude-dirs` | No | "build,target,dist,node_modules,.gradle,.idea,out" | Directories to exclude from LOC count |
| `test-timeout-minutes` | No | 30 | Test timeout in minutes |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `TAILSCALE_AUTHKEY` | Yes | Tailscale authentication key |
| `GHL_USERNAME` | Yes | GitHub username for Gradle dependencies |
| `GHL_PASSWORD` | Yes | GitHub token for Gradle dependencies |

### Example Usage:
```yaml
jobs:
  code-coverage:
    uses: monta-app/github-workflows/.github/workflows/code-coverage-kotlin.yml@main
    with:
      service-name: "my-kotlin-service"
      java-version: "21"
    secrets:
      TAILSCALE_AUTHKEY: ${{ secrets.TAILSCALE_AUTHKEY }}
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
```

---

## Component Build

**File:** `component-build.yml`  
**Purpose:** Builds multi-architecture Docker images and pushes them to Amazon ECR.

### What it does:
1. Updates Slack with build progress
2. Builds Docker images for both AMD64 and ARM64 architectures
3. Pushes images to ECR with architecture-specific tags
4. Creates a multi-arch manifest
5. Notifies Slack of build completion

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `stage` | Yes | - | Deployment stage: "dev", "staging", or "production" |
| `service-name` | Yes | - | Display name (e.g., "OCPP Service") |
| `service-emoji` | Yes | - | Emoji for Slack notifications |
| `service-identifier` | Yes | - | Service identifier (e.g., "ocpp", "vehicle") |
| `runner-size` | No | "normal" | Runner size: "normal" or "large" |
| `region` | No | "eu-west-1" | AWS region |
| `docker-file-name` | No | "Dockerfile" | Dockerfile name |
| `additional-build-args` | No | - | Additional Docker build arguments |
| `ecr-repository-name` | No | - | Custom ECR repository name |
| `slack-message-id` | No | - | Existing Slack message ID to update |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `AWS_ACCOUNT_ID` | Yes | AWS account ID |
| `SLACK_APP_TOKEN` | Yes | Slack app token |
| `GHL_USERNAME` | No | GitHub username (required for Kotlin) |
| `GHL_PASSWORD` | No | GitHub token (required for Kotlin) |
| `SENTRY_AUTH_TOKEN` | No | Sentry authentication token |
| `AWS_CDN_ACCESS_KEY_ID` | No | CDN access key ID |
| `AWS_CDN_SECRET_ACCESS_KEY` | No | CDN secret access key |

### Outputs:
- `image-tag`: The SHA tag of the built image

### Example Usage:
```yaml
jobs:
  build:
    uses: monta-app/github-workflows/.github/workflows/component-build.yml@main
    with:
      stage: "staging"
      service-name: "Vehicle Service"
      service-emoji: "🚗"
      service-identifier: "vehicle"
    secrets:
      AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

---

## Component Deploy

**File:** `component-deploy.yml`  
**Purpose:** Deploys a service by updating Kubernetes manifests in the kube-manifests repository.

### What it does:
1. Updates Slack with deployment progress
2. Checks out the kube-manifests repository
3. Updates image tag and metadata in values.yaml
4. Updates deployment history in config.yaml
5. Commits and pushes changes to trigger ArgoCD deployment
6. Notifies Slack of deployment status

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `stage` | Yes | - | Deployment stage: "dev", "staging", or "production" |
| `service-name` | Yes | - | Display name (e.g., "OCPP Service") |
| `service-emoji` | Yes | - | Emoji for Slack notifications |
| `service-identifier` | Yes | - | Service identifier (e.g., "ocpp", "vehicle") |
| `image-tag` | Yes | - | Docker image tag to deploy |
| `slack-message-id` | No | - | Existing Slack message ID to update |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `MANIFEST_REPO_PAT` | Yes | GitHub PAT for kube-manifests repo |
| `SLACK_APP_TOKEN` | Yes | Slack app token |

### Outputs:
- `slack-message-id`: Slack message ID for updates

### Example Usage:
```yaml
jobs:
  deploy:
    uses: monta-app/github-workflows/.github/workflows/component-deploy.yml@main
    with:
      stage: "production"
      service-name: "Payment Service"
      service-emoji: "💳"
      service-identifier: "payment"
      image-tag: "abc123def456"
    secrets:
      MANIFEST_REPO_PAT: ${{ secrets.MANIFEST_REPO_PAT }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

---

## Component Initialize

**File:** `component-initialize.yml`  
**Purpose:** Initializes the CI/CD pipeline by creating a Slack notification message.

### What it does:
1. Creates an initial Slack message for tracking pipeline progress
2. Returns the message ID for subsequent workflow updates

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service-name` | Yes | - | Display name (e.g., "OCPP Service") |
| `service-emoji` | Yes | - | Emoji for Slack notifications |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `SLACK_APP_TOKEN` | Yes | Slack app token |

### Outputs:
- `slack-message-id`: Slack message ID for updates
- `slack-channel-id`: Slack channel ID

### Example Usage:
```yaml
jobs:
  init:
    uses: monta-app/github-workflows/.github/workflows/component-initialize.yml@main
    with:
      service-name: "User Service"
      service-emoji: "👤"
    secrets:
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

---

## Component Test (Kotlin)

**File:** `component-test-kotlin.yml`  
**Purpose:** Runs tests for Kotlin projects with Gradle.

### What it does:
1. Sets up Java environment
2. Runs Gradle tests
3. Uploads test results as artifacts
4. Updates Slack with test status

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | - | Runner size for the job |
| `service-name` | No | - | Display name for Slack |
| `service-emoji` | No | - | Emoji for Slack |
| `gradle-module` | No | - | Gradle module name |
| `java-version` | No | "21" | Java version |
| `slack-message-id` | No | - | Slack message ID to update |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `GHL_USERNAME` | Yes | GitHub username |
| `GHL_PASSWORD` | Yes | GitHub token |
| `SLACK_APP_TOKEN` | Yes | Slack app token |

### Example Usage:
```yaml
jobs:
  test:
    uses: monta-app/github-workflows/.github/workflows/component-test-kotlin.yml@main
    with:
      java-version: "21"
      service-name: "API Service"
      service-emoji: "🔌"
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

---

## Component Test (Python)

**File:** `component-test-python.yml`  
**Purpose:** Runs tests for Python projects using pytest with uv.

### What it does:
1. Sets up Python environment
2. Optionally starts Docker Compose services if `docker-compose-path` is provided
3. Waits for Docker containers to be healthy
4. Creates .env file from `TEST_ENV_FILE` secret if provided
5. Installs uv for fast dependency management
6. Runs `uv sync` to install dependencies from `pyproject.toml`
7. Executes pytest with HTML and JUnit reports
8. Uploads test results as artifacts
9. Updates Slack with test status

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | - | Runner size for the job |
| `service-name` | No | - | Display name for Slack |
| `service-emoji` | No | - | Emoji for Slack |
| `python-version` | No | "3.13" | Python version |
| `test-directory` | No | "tests" | Directory containing test files |
| `pytest-args` | No | "" | Additional pytest arguments |
| `docker-compose-path` | No | - | File path of the docker compose file |
| `slack-message-id` | No | - | Slack message ID to update |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `SLACK_APP_TOKEN` | Yes | Slack app token |
| `TEST_ENV_FILE` | No | Environment variables for tests in .env format |

### Requirements:
- Project must use `pyproject.toml` for dependency management
- Test dependencies should be included in dev dependencies

### Example Usage:
```yaml
jobs:
  test:
    uses: monta-app/github-workflows/.github/workflows/component-test-python.yml@main
    with:
      python-version: "3.13"
      test-directory: "tests"
      service-name: "ML Service"
      service-emoji: "🤖"
    secrets:
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
      TEST_ENV_FILE: ${{ secrets.TEST_ENV_FILE }}
```

---

## Deploy Kotlin

**File:** `deploy-kotlin.yml`  
**Purpose:** Complete CI/CD pipeline for Kotlin services including testing, building Docker images, and deploying to Kubernetes.

### What it does:
1. **Create Release Tag** (optional): Creates a release tag when triggered via workflow_dispatch and `enable-release-tag` is true
2. **Initialize**: Sets up Slack notifications for the deployment process
3. **Test**: Runs unit tests and validates code quality
4. **Build**: Creates multi-architecture Docker images and pushes to ECR
5. **Deploy**: Updates Kubernetes manifests for deployment
6. **Create Changelog** (optional): Generates and publishes changelog to Slack and GitHub releases

### Job Execution Flow:
The workflow uses conditional execution to ensure proper handling of optional features:
- **Create Release Tag**: Only runs when `enable-release-tag: true` AND triggered via `workflow_dispatch`
- **Initialize**: Always runs if release tag job succeeded or was skipped
- **Test & Build**: Run in parallel after Initialize succeeds, using `if: always()` to handle skipped dependencies
- **Deploy**: Only runs when ALL required jobs (Initialize, Test, Build) succeed
- **Create Changelog**: Only runs when `enable-changelog: true` AND Deploy succeeds

This conditional logic ensures the workflow continues properly even when optional features are disabled.

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size: "normal" or "large" |
| `stage` | Yes | - | Deployment stage: "dev", "staging", or "production" |
| `service-name` | Yes | - | Human-readable service name (e.g., "Charging Service") |
| `service-emoji` | Yes | - | Emoji to identify the service in Slack notifications |
| `service-identifier` | Yes | - | Service identifier for ECR and Kubernetes (e.g., "charging") |
| `gradle-module` | No | - | Gradle module name for multi-module projects |
| `java-version` | No | "21" | Java version to use |
| `gradle-args` | No | "--no-daemon --parallel" | Additional Gradle arguments |
| `region` | No | "eu-west-1" | AWS region for deployment |
| `docker-file-name` | No | "Dockerfile" | Name of the Dockerfile to build |
| `additional-build-args` | No | - | Additional Docker build arguments |
| `ecr-repository-name` | No | - | Override ECR repository name |
| `enable-release-tag` | No | false | Enable automatic release tag creation on workflow_dispatch |
| `release-tag-prefix` | No | '' | Optional prefix for release tag names. If provided, creates tags like 'prefix-YYYY-MM-DD-HH-MM' |
| `enable-changelog` | No | false | Enable changelog generation after deployment |
| `changelog-tag-pattern` | No | - | Regex pattern for matching tag patterns (group 1 should match version) - example: processor-(.*) |
| `changelog-path-exclude-pattern` | No | - | Regex pattern for excluding file paths from changelog - example: ^gateway/ |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `GHL_USERNAME` | Yes | GitHub username for Gradle dependencies |
| `GHL_PASSWORD` | Yes | GitHub token for Gradle dependencies |
| `AWS_ACCOUNT_ID` | Yes | AWS Account ID for ECR and deployment |
| `SLACK_APP_TOKEN` | Yes | Slack token for notifications |
| `MANIFEST_REPO_PAT` | Yes | GitHub PAT for updating kube-manifests |
| `SENTRY_AUTH_TOKEN` | No | Sentry authentication token |
| `AWS_CDN_ACCESS_KEY_ID` | No | CDN access key for S3 access |
| `AWS_CDN_SECRET_ACCESS_KEY` | No | CDN secret key for S3 access |

### Example Usage:

#### Basic Deployment:
```yaml
name: Deploy to Production
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: monta-app/github-workflows/.github/workflows/deploy-kotlin.yml@main
    with:
      stage: "production"
      service-name: "Charging Service"
      service-emoji: "⚡"
      service-identifier: "charging"
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      AWS_ACCOUNT_ID: ${{ secrets.PRODUCTION_AWS_ACCOUNT_ID }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
      MANIFEST_REPO_PAT: ${{ secrets.MANIFEST_REPO_PAT }}
```

#### With Release Management:
```yaml
name: Deploy Production with Release
on:
  push:
    tags: ['*']
  workflow_dispatch:

jobs:
  deploy:
    uses: monta-app/github-workflows/.github/workflows/deploy-kotlin.yml@main
    with:
      stage: "production"
      runner-size: "large"
      service-name: "Charging Service"
      service-emoji: "⚡"
      service-identifier: "charging"
      gradle-module: "charging-service"
      enable-release-tag: true    # Creates tag on manual trigger
      enable-changelog: true      # Generates changelog after deploy
      # Optional: Prefix for release tags
      release-tag-prefix: "charging"  # Creates tags like 'charging-2024-01-15-14-30'
      # Optional: Filter changelog by tag pattern (e.g., for monorepo)
      changelog-tag-pattern: "charging-(.*)"
      # Optional: Exclude paths from changelog (e.g., other services)
      changelog-path-exclude-pattern: "^(payment|vehicle)/"
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      AWS_ACCOUNT_ID: ${{ secrets.PRODUCTION_AWS_ACCOUNT_ID }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
      MANIFEST_REPO_PAT: ${{ secrets.MANIFEST_REPO_PAT }}
      SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
```

---

## Deploy Python

**File:** `deploy-python.yml`  
**Purpose:** Complete CI/CD pipeline for Python services (test → build → deploy).

### What it does:
1. Initializes Slack notification
2. Runs Python tests using pytest and uv
3. Builds multi-arch Docker images
4. Deploys to Kubernetes via manifest updates

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size ("normal" or "large") |
| `stage` | **Yes** | - | Deployment stage (dev/staging/production) |
| `service-name` | **Yes** | - | Service display name |
| `service-emoji` | **Yes** | - | Service emoji |
| `service-identifier` | **Yes** | - | Service identifier for K8s |
| `region` | No | "eu-west-1" | AWS region |
| `docker-file-name` | No | "Dockerfile" | Dockerfile name |
| `additional-build-args` | No | - | Extra Docker build args |
| `ecr-repository-name` | No | - | ECR repository override |
| `docker-compose-path` | No | - | File path of the docker compose file |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `AWS_ACCOUNT_ID` | **Yes** | AWS account for ECR |
| `SLACK_APP_TOKEN` | **Yes** | Slack app token |
| `MANIFEST_REPO_PAT` | **Yes** | GitHub PAT for manifest repo |
| `SENTRY_AUTH_TOKEN` | No | Sentry auth token |
| `AWS_CDN_ACCESS_KEY_ID` | No | CDN access key |
| `AWS_CDN_SECRET_ACCESS_KEY` | No | CDN secret key |
| `TEST_ENV_FILE` | No | Environment variables for tests in .env format |

### Requirements:
- Python project with `pyproject.toml`
- Tests in `tests/` directory (configurable)
- Dockerfile for containerization

### Example Usage:
```yaml
name: Deploy to Production
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: monta-app/github-workflows/.github/workflows/deploy-python.yml@main
    with:
      stage: "production"
      service-name: "ML Service"
      service-emoji: "🤖"
      service-identifier: "ml-service"
      region: "eu-west-1"
    secrets:
      AWS_ACCOUNT_ID: ${{ secrets.AWS_ACCOUNT_ID }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
      MANIFEST_REPO_PAT: ${{ secrets.MANIFEST_REPO_PAT }}
      TEST_ENV_FILE: ${{ secrets.TEST_ENV_FILE }}
```

---

## Publish Tech Docs

**File:** `publish-tech-docs.yml`  
**Purpose:** Publishes technical documentation to Backstage via AWS S3.

### What it does:
1. Sets up Node.js and Python environments
2. Installs techdocs-cli and mkdocs
3. Generates documentation site
4. Publishes to S3 bucket for Backstage

### Inputs:
None - uses repository name as entity name

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `TECHDOCS_AWS_ACCESS_KEY_ID` | Yes | AWS access key for S3 |
| `TECHDOCS_AWS_SECRET_ACCESS_KEY` | Yes | AWS secret key for S3 |

### Example Usage:
```yaml
jobs:
  publish-docs:
    uses: monta-app/github-workflows/.github/workflows/publish-tech-docs.yml@main
    secrets:
      TECHDOCS_AWS_ACCESS_KEY_ID: ${{ secrets.TECHDOCS_AWS_ACCESS_KEY_ID }}
      TECHDOCS_AWS_SECRET_ACCESS_KEY: ${{ secrets.TECHDOCS_AWS_SECRET_ACCESS_KEY }}
```

---

## Pull Request Kotlin

**File:** `pull-request-kotlin.yml`  
**Purpose:** Validates Kotlin pull requests with linting, testing, and code coverage.

### What it does:
1. Validates PR title format
2. Runs Kotlin linter (ktlint)
3. Executes tests with Kover coverage
4. Uploads results to SonarCloud
5. Comments coverage report on PR
6. Publishes test results

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size |
| `java-version` | No | "21" | Java version |
| `gradle-module` | No | - | Gradle module name |
| `kover-report-path` | No | "build/reports/kover/report.xml" | Kover report path |
| `test-timeout-minutes` | No | 30 | Test timeout |
| `skip-sonar` | No | false | Skip SonarCloud analysis |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `GHL_USERNAME` | Yes | GitHub username |
| `GHL_PASSWORD` | Yes | GitHub token |
| `SONAR_TOKEN` | Yes | SonarCloud token |

### Example Usage:
```yaml
name: PR Validation
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate:
    uses: monta-app/github-workflows/.github/workflows/pull-request-kotlin.yml@main
    with:
      java-version: "21"
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

---

## Pull Request React (Bun)

**File:** `pull-request-react-bun.yml`  
**Purpose:** Validates React/TypeScript pull requests using Bun runtime with code coverage reporting.

### What it does:
1. Validates PR title format
2. Starts optional Docker Compose services if `docker-compose-path` is provided
3. Waits for Docker containers to be healthy
4. Installs dependencies with Bun
5. Runs linter
6. Runs tests (if configured)
7. Builds the project
8. Reports code coverage using LCOV format

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size |
| `bun-version` | No | "latest" | Bun version |
| `working-directory` | No | "." | Frontend code directory |
| `build-timeout-minutes` | No | 15 | Build timeout |
| `lint-command` | No | "bun run lint" | Lint command |
| `build-command` | No | "bun run build" | Build command |
| `test-command` | No | "bun run test" | Test command (optional) |
| `docker-compose-path` | No | - | Path to Docker Compose file for services |

### Example Usage:
```yaml
name: PR Validation
on:
  pull_request:

jobs:
  validate:
    uses: monta-app/github-workflows/.github/workflows/pull-request-bun.yml@main
    with:
      working-directory: "./frontend"
      lint-command: "bun run lint:all"
      docker-compose-path: "docker-compose.test.yml"
```

### Code Coverage:
The workflow automatically reports code coverage if your project generates LCOV coverage files in the `coverage/` directory. The coverage report is posted as a comment on the pull request.

---

## Pull Request React (pnpm)

**File:** `pull-request-react-pnpm.yml`  
**Purpose:** Validates React/TypeScript pull requests using pnpm package manager.

### What it does:
1. Validates PR title format
2. Sets up pnpm and Node.js
3. Installs dependencies
4. Runs linter
5. Runs tests (if configured)
6. Builds the project

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size |
| `node-version` | No | "lts/jod" | Node.js version |
| `pnpm-version` | No | "10" | pnpm version |
| `working-directory` | No | "." | Frontend code directory |
| `build-timeout-minutes` | No | 15 | Build timeout |
| `lint-command` | No | "pnpm run lint" | Lint command |
| `build-command` | No | "pnpm run build" | Build command |
| `test-command` | No | "pnpm run test" | Test command (optional) |

### Example Usage:
```yaml
name: PR Validation
on:
  pull_request:

jobs:
  validate:
    uses: monta-app/github-workflows/.github/workflows/pull-request-react.yml@main
    with:
      node-version: "20"
      pnpm-version: "9"
```

---

## Rollback

**File:** `rollback.yml`  
**Purpose:** Rolls back a service deployment to a previous commit by updating Kubernetes manifests.

### What it does:
1. Sends a Slack notification about the rollback (if not in dry-run mode)
2. Identifies the commit to roll back to (defaults to the previous commit)
3. Updates the Kubernetes manifests in the kube-manifests repository
4. Updates the image tag and revision in values.yaml
5. Updates deployment history in config.yaml
6. Optionally blocks further deployments by calling the block-deploys workflow

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `commit-sha` | No | HEAD^ | Commit to roll back to (defaults to previous commit) |
| `service-name` | Yes | - | Proper name for your service (e.g., "OCPP Service") |
| `service-identifier` | Yes | - | Identifier of the service (e.g., "ocpp", "vehicle") |
| `slack-channel` | Yes | - | Slack channel for rollback notifications |
| `environment` | Yes | - | Deployment environment: "dev", "staging", or "production" |
| `dry-run` | No | false | Set to true to show rollback without pushing (disables Slack) |
| `block-workflow` | No | - | Name of workflow to block after rollback (e.g., "deploy-production.yml") |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `SLACK_WEBHOOK` | Yes | Slack webhook URL for notifications |
| `ADMIN_PAT` | Yes | GitHub PAT for updating workflows and pushing to kube-manifests repo |

### Example Usage:
```yaml
jobs:
  rollback:
    uses: monta-app/github-workflows/.github/workflows/rollback.yml@main
    with:
      service-name: "Charging Service"
      service-identifier: "charging"
      slack-channel: "#deploys"
      environment: "production"
      block-workflow: "deploy-production.yml"
    secrets:
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
      ADMIN_PAT: ${{ secrets.PAT }}
```

---

## SonarCloud Analysis

**File:** `sonar-cloud.yml`  
**Purpose:** Runs dedicated SonarCloud analysis for code quality metrics.

### What it does:
1. Checks out code with full history
2. Sets up Java environment
3. Caches SonarCloud packages
4. Runs Kover coverage report
5. Uploads analysis to SonarCloud

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | No | "normal" | Runner size |
| `java-version` | No | "21" | Java version |
| `gradle-module` | No | - | Gradle module name |

### Secrets:
| Secret | Required | Description |
|--------|----------|-------------|
| `GHL_USERNAME` | Yes | GitHub username |
| `GHL_PASSWORD` | Yes | GitHub token |
| `SONAR_TOKEN` | Yes | SonarCloud token |

### Example Usage:
```yaml
jobs:
  sonarcloud:
    uses: monta-app/github-workflows/.github/workflows/sonar-cloud.yml@main
    with:
      java-version: "21"
    secrets:
      GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
      GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

---

## Track Pending Release

**File:** `track-pending-release.yml`
**Purpose:** For repositories where production releases are triggered manually (via workflow dispatch or tags), this workflow maintains a persistent GitHub issue that shows at a glance what commits are pending deployment. The issue title uses color-coded emoji indicators to quickly show deployment status in your issue list.

### How it works:
- Compares latest production release tag with main branch
- Creates/updates a persistent GitHub issue with status emoji in title
- Shows commit list with links and deployment instructions
- Updates automatically on every push to main and after production deployments

### Status Indicators:
- **🟢 Green**: Production is up-to-date (0 commits)
- **🟡 Yellow**: 1 commit pending
- **🔴 Red**: Multiple commits pending

### Inputs:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `main-branch` | No | "main" | Main branch name to track |
| `production-workflow` | No | "deploy-production.yml" | Production deployment workflow filename |

### Secrets:
None required - uses `GITHUB_TOKEN` which is automatically provided by GitHub Actions.

### Requirements:
- Service must use `enable-release-tag: true` in production deployment workflow
- Production deployment must create git tags (used to identify deployed version)

### Example Usage:

#### Basic Setup (Caller Workflow):
```yaml
name: Track Pending Release

on:
  push:
    branches:
      - main
    tags:
      - '*'
  workflow_dispatch:
  workflow_run:
    workflows: ["Deploy Production"]  # Must match your production workflow name
    types:
      - completed

jobs:
  track-release:
    uses: monta-app/github-workflows/.github/workflows/track-pending-release.yml@main
    with:
      main-branch: 'main'
      production-workflow: 'deploy-production.yml'
```

**Important:** The `workflow_run` trigger is required because `enable-release-tag` creates tags using `GITHUB_TOKEN`, which doesn't trigger other workflows. This ensures the tracker updates immediately after production deploys.

#### Custom Branch:
```yaml
jobs:
  track-release:
    uses: monta-app/github-workflows/.github/workflows/track-pending-release.yml@main
    with:
      main-branch: 'master'
      production-workflow: 'deploy-prod.yml'
```

### What the issue looks like:
- **Title:** `🟢 Production Release Tracker` (changes to 🟡 or 🔴 based on pending commits)
- **Body:** Shows latest deploy tag, current main commit, and list of pending commits with links
- **When up-to-date:** Displays "Recently Released" confirmation message
- **When pending:** Shows commit list with direct link to trigger deployment via workflow dispatch

### Requirements:
- Service must use `enable-release-tag: true` in production deployment workflow (creates the tags this workflow tracks)

### Best Practices:
1. Pin the issue for easy team access
2. Include tag trigger (`tags: ['*']`) to update immediately after production deploys
3. Pairs well with `enable-changelog: true` for automated release notes

---

## Implementation Guide

### Setting Up Secrets

These workflows use **organization-level secrets** that are automatically available to all **private** repositories in the `monta-app` org. You do not need to add them manually — just reference the correct name when passing secrets to a workflow.

> **Public repositories** do not have access to org secrets. If your repo is public, you must add required secrets at the repository level.

#### Organization Secrets Reference

**GitHub & Authentication:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `GHL_USERNAME` | build, test, deploy-kotlin, pull-request-kotlin, sonar-cloud | GitHub username for package registry access |
| `GHL_PASSWORD` | build, test, deploy-kotlin, pull-request-kotlin, sonar-cloud | GitHub PAT with `read:packages` scope |
| `PAT` | deploy workflows | PAT with write access to manifest repos (passed as `MANIFEST_REPO_PAT`) |
| `MONTA_BOT_TOKEN` | changelog-cli-action | GitHub token for creating releases and PR comments |
| `SSH_KEY_MONTA_BOT` | service-profile-kotlin | SSH key for cross-repo access |

**AWS:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `INTERNAL_AWS_ACCOUNT_ID` | build, deploy workflows | AWS account ID (passed as `AWS_ACCOUNT_ID`) |
| `PRODUCTION_AWS_ACCOUNT_ID` | deploy workflows (production) | Production AWS account ID |
| `STAGING_AWS_ACCOUNT_ID` | deploy workflows (staging) | Staging AWS account ID |
| `ECR_AWS_ACCESS_KEY_ID` | legacy deploy workflows | ECR access key |
| `ECR_AWS_SECRET_ACCESS_KEY` | legacy deploy workflows | ECR secret key |
| `TECHDOCS_AWS_ACCESS_KEY_ID` | publish-tech-docs | TechDocs S3 access key |
| `TECHDOCS_AWS_SECRET_ACCESS_KEY` | publish-tech-docs | TechDocs S3 secret key |
| `CDN_PRODUCTION_ACCESS_KEY` | build (via `AWS_CDN_ACCESS_KEY_ID`) | CDN access for production builds |
| `CDN_PRODUCTION_SECRET_ACCESS_KEY` | build (via `AWS_CDN_SECRET_ACCESS_KEY`) | CDN secret for production builds |
| `CDN_STAGING_ACCESS_KEY` | build (via `AWS_CDN_ACCESS_KEY_ID`) | CDN access for staging builds |
| `CDN_STAGING_SECRET_ACCESS_KEY` | build (via `AWS_CDN_SECRET_ACCESS_KEY`) | CDN secret for staging builds |

**Deployment & ArgoCD:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `ARGOCD_TOKEN_PRODUCTION` | deploy workflows (passed as `ARGOCD_TOKEN`) | ArgoCD auth for production deployments |
| `ARGOCD_TOKEN_STAGING` | deploy workflows (passed as `ARGOCD_TOKEN`) | ArgoCD auth for staging deployments |
| `INFRA_PORTAL_TOKEN_PRODUCTION` | service-ocpp gateway | Infra Portal API auth for production |
| `INFRA_PORTAL_TOKEN_STAGING` | service-ocpp, service-support, data services | Infra Portal API auth for staging |
| `SLACK_APP_TOKEN` | all deploy/build workflows | Slack notifications for build and deploy status |
| `SLACK_WEBHOOK` | rollback | Slack webhook for rollback notifications |
| `SLACK_DEPLOYMENT_WEBHOOK_URL` | service-user, service-kratos, service-roaming-prices | Legacy Slack webhook for deploy notifications |
| `SENTRY_AUTH_TOKEN` | build workflows | Sentry release tracking (optional) |
| `WEBAPPS_DEPLOY_TOKEN` | web app deployments | Web application deploy token |

**Changelog & Jira:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `JIRA_EMAIL` | deploy-kotlin, changelog-cli-action | Jira API authentication email |
| `JIRA_TOKEN` | deploy-kotlin, changelog-cli-action | Jira API authentication token |
| `MONTA_BOT_TOKEN` | changelog-cli-action | GitHub token (used as `github-token` and `CHANGELOG_GITHUB_TOKEN`) |

**Code Quality & Testing:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `SONAR_TOKEN` | sonar-cloud, pull-request-kotlin, code-coverage-kotlin | SonarCloud analysis |
| `TAILSCALE_AUTHKEY` | code-coverage-kotlin | VPN access for integration tests |
| `TEST_VISIBILITY_DB_PASSWORD` | server (unit-tests, integration-tests) | Upload test results to test visibility DB |
| `K6_PRODUCTION_USERNAME` / `K6_PRODUCTION_PASSWORD` | grafana-k6 | k6 browser test credentials (production) |
| `K6_STAGING_USERNAME` / `K6_STAGING_PASSWORD` | grafana-k6 | k6 browser test credentials (staging) |
| `K6_GRAFANA_AUTH_TOKEN` | grafana-k6 | k6 Grafana Cloud integration |
| `K6_GRAFANA_SM_ACCESS_TOKEN` | grafana-k6 | k6 Grafana synthetic monitoring |
| `K6_GRAFANA_URL` | grafana-k6 | k6 Grafana endpoint URL |

**Localization:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `LOKALISE_TOKEN` | service-wallet, service-grid (via deploy-kotlin) | Lokalise API token for fetching translations during build |
| `LOKALISE_PROJECT_ID` | service-wallet, service-grid (via deploy-kotlin) | Lokalise project identifier |

**Other:**

| Secret | Used by | Purpose |
|--------|---------|---------|
| `POSTHOG_API_KEY` | analytics workflows | PostHog product analytics |
| `GRAFANA_CLOUD_MONTA_BOT_TOKEN` | monitoring workflows | Grafana Cloud access |
| `PRODUCTION_AWS_ACCESS_KEY_ID` / `PRODUCTION_AWS_SECRET_ACCESS_KEY` | server, dbt-pipeline, data services, legacy deploys | AWS credentials for production (legacy pattern — prefer IAM role-based `AWS_ACCOUNT_ID`) |
| `STAGING_AWS_ACCESS_KEY_ID` / `STAGING_AWS_SECRET_ACCESS_KEY` | legacy deploy workflows | AWS credentials for staging |
| `DEV_AWS_ACCESS_KEY_ID` / `DEV_AWS_SECRET_ACCESS_KEY` | service-roaming-prices | AWS credentials for dev environment |
| `STAGING_KUBECONFIG` / `STAGING_KUBECONFIG_BASE64` | frontend-monorepo (PR preview deploys) | Kubernetes config for staging cluster |

**Likely Deprecated (no workflow references found):**

| Secret | Last Updated | Notes |
|--------|-------------|-------|
| `BRANCH_TO_ENV_DEVELOPMENT` | 5 years ago | No references found — likely from old deploy pattern |
| `BRANCH_TO_ENV_MASTER` | 6 years ago | No references found |
| `BRANCH_TO_ENV_STAGING` | 6 years ago | No references found |
| `DEV_KUBECONFIG` / `DEV_KUBECONFIG_BASE` | 4 years ago | No references found — dev cluster may no longer exist |
| `FLUTTER_AWS_ACCESS_KEY_ID` / `FLUTTER_AWS_SECRET_ACCESS_KEY` | 3 years ago | No references found — Flutter builds may use different approach now |
| `K8S_SERVICE_PROFILE_OCPP_STAGING` / `K8S_SERVICE_PROFILE_STAGING` | 7 months ago | No references found |
| `SSH_KEY_LIB_ARCHITECTURE` / `SSH_KEY_LIB_ELECTRA` | 3 years ago | No references found — libraries may have moved to package registry |
| `SLACK_BOT_TOKEN` | 5 years ago | No references found — replaced by `SLACK_APP_TOKEN` |
| `VAPOR_API_TOKEN` | 6 years ago | No references found — Vapor (Swift) likely no longer used |

#### Common Secret Mappings

Some org secrets have different names than what workflows expect. Here are the most common mappings:

```yaml
# In your workflow file:
secrets:
  AWS_ACCOUNT_ID: ${{ secrets.INTERNAL_AWS_ACCOUNT_ID }}      # or PRODUCTION_AWS_ACCOUNT_ID / STAGING_AWS_ACCOUNT_ID
  MANIFEST_REPO_PAT: ${{ secrets.PAT }}
  ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN_PRODUCTION }}         # or ARGOCD_TOKEN_STAGING
  CHANGELOG_GITHUB_TOKEN: ${{ secrets.MONTA_BOT_TOKEN }}
  AWS_CDN_ACCESS_KEY_ID: ${{ secrets.CDN_PRODUCTION_ACCESS_KEY }}  # or CDN_STAGING_ACCESS_KEY
  AWS_CDN_SECRET_ACCESS_KEY: ${{ secrets.CDN_PRODUCTION_SECRET_ACCESS_KEY }}  # or CDN_STAGING_SECRET_ACCESS_KEY
  # These are passed directly (org name = workflow name):
  GHL_USERNAME: ${{ secrets.GHL_USERNAME }}
  GHL_PASSWORD: ${{ secrets.GHL_PASSWORD }}
  SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
  JIRA_EMAIL: ${{ secrets.JIRA_EMAIL }}
  JIRA_TOKEN: ${{ secrets.JIRA_TOKEN }}
  SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
  SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

#### Secrets per Workflow

Quick reference for which secrets each workflow needs:

| Workflow | Required Secrets | Optional Secrets |
|----------|-----------------|------------------|
| `component-build.yml` | `AWS_ACCOUNT_ID`, `SLACK_APP_TOKEN` | `GHL_USERNAME`, `GHL_PASSWORD`, `SENTRY_AUTH_TOKEN`, `AWS_CDN_ACCESS_KEY_ID`, `AWS_CDN_SECRET_ACCESS_KEY`, `LOKALISE_TOKEN`, `LOKALISE_PROJECT_ID` |
| `component-deploy-v2.yml` | `MANIFEST_REPO_PAT`, `SLACK_APP_TOKEN` | `ARGOCD_TOKEN` |
| `deploy-generic-v2.yml` | `AWS_ACCOUNT_ID`, `SLACK_APP_TOKEN`, `MANIFEST_REPO_PAT` | `SENTRY_AUTH_TOKEN`, `AWS_CDN_ACCESS_KEY_ID`, `AWS_CDN_SECRET_ACCESS_KEY`, `TEST_ENV_FILE`, `ARGOCD_TOKEN` |
| `deploy-kotlin.yml` | `GHL_USERNAME`, `GHL_PASSWORD`, `AWS_ACCOUNT_ID`, `SLACK_APP_TOKEN`, `MANIFEST_REPO_PAT` | `SENTRY_AUTH_TOKEN`, `AWS_CDN_ACCESS_KEY_ID`, `AWS_CDN_SECRET_ACCESS_KEY`, `LOKALISE_TOKEN`, `LOKALISE_PROJECT_ID`, `JIRA_EMAIL`, `JIRA_TOKEN`, `CHANGELOG_GITHUB_TOKEN`, `ARGOCD_TOKEN` |
| `publish-tech-docs.yml` | `TECHDOCS_AWS_ACCESS_KEY_ID`, `TECHDOCS_AWS_SECRET_ACCESS_KEY` | — |
| `sonar-cloud.yml` | `GHL_USERNAME`, `GHL_PASSWORD`, `SONAR_TOKEN` | — |
| `code-coverage-kotlin.yml` | `GHL_USERNAME`, `GHL_PASSWORD`, `SONAR_TOKEN` | `TAILSCALE_AUTHKEY` |
| `changelog-cli-action` (direct) | `MONTA_BOT_TOKEN`, `JIRA_EMAIL`, `JIRA_TOKEN`, `SLACK_APP_TOKEN` | — |

### Repository Structure Requirements

- **Kotlin Projects:**
  - Must have Gradle build configuration
  - Should include Kover plugin for coverage
  - SonarCloud configuration in `build.gradle.kts`

- **React Projects:**
  - Package.json with lint, build, and test scripts
  - TypeScript configuration
  - Either Bun or pnpm as package manager

- **Kubernetes Deployments:**
  - Manifests must be in `kube-manifests` repository
  - Structure: `apps/<service-identifier>/<stage>/app/values.yaml`
  - Config file: `apps/<service-identifier>/<stage>/cluster/config.yaml`

### Best Practices

1. **Version Pinning:** Always use a specific version tag (e.g., `@main`) when calling workflows
2. **Runner Sizing:** Use "large" runners for resource-intensive builds
3. **Timeouts:** Adjust timeouts based on your project's build/test duration
4. **Slack Integration:** Use consistent service names and emojis across workflows
5. **Multi-Module Projects:** Specify `gradle-module` for targeted builds
6. **Environment Stages:** Use consistent stage names: "dev", "staging", "production"

### Troubleshooting

**Common Issues:**

1. **Gradle Build Failures:**
   - Ensure `GHL_USERNAME` and `GHL_PASSWORD` secrets are set
   - Check that GitHub packages are properly configured

2. **Docker Build Failures:**
   - Verify Dockerfile exists at specified path
   - Check build arguments syntax
   - Ensure secrets are passed correctly

3. **Deployment Failures:**
   - Verify manifest repository structure
   - Check PAT permissions for kube-manifests
   - Ensure service identifier matches manifest paths

4. **Coverage Report Issues:**
   - Verify Kover plugin is configured
   - Check report path matches actual output
   - Ensure tests generate coverage data

For additional support, check the workflow logs in GitHub Actions or contact the platform team.
