# GitHub Workflows Documentation Guide

This guide provides a comprehensive overview of all reusable GitHub workflows in this repository. Each workflow is designed to be called from your repository's workflows to standardize CI/CD processes across projects.

## Table of Contents

1. [Code Coverage (Kotlin)](#code-coverage-kotlin)
2. [Component Build](#component-build)
3. [Component Deploy](#component-deploy)
4. [Component Initialize](#component-initialize)
5. [Component Test (Kotlin)](#component-test-kotlin)
6. [Deploy Kotlin](#deploy-kotlin)
7. [Publish Tech Docs](#publish-tech-docs)
8. [Pull Request Kotlin](#pull-request-kotlin)
9. [Pull Request React (Bun)](#pull-request-react-bun)
10. [Pull Request React (pnpm)](#pull-request-react-pnpm)
11. [SonarCloud Analysis](#sonarcloud-analysis)

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
| `enable-changelog` | No | false | Enable changelog generation after deployment |

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

## Implementation Guide

### Setting Up Secrets

Most workflows require organization or repository secrets. Add these in your repository settings:

1. **GitHub Tokens:**
   - `GHL_USERNAME`: Your GitHub username
   - `GHL_PASSWORD`: A GitHub personal access token with `read:packages` scope
   - `MANIFEST_REPO_PAT`: PAT with write access to kube-manifests repo

2. **AWS Credentials:**
   - `AWS_ACCOUNT_ID`: Your AWS account ID
   - `TECHDOCS_AWS_ACCESS_KEY_ID`: AWS access key for TechDocs S3
   - `TECHDOCS_AWS_SECRET_ACCESS_KEY`: AWS secret key for TechDocs S3

3. **Third-party Services:**
   - `SLACK_APP_TOKEN`: Slack app-level token
   - `SONAR_TOKEN`: SonarCloud authentication token
   - `TAILSCALE_AUTHKEY`: Tailscale VPN authentication key
   - `SENTRY_AUTH_TOKEN`: Sentry authentication token (optional)

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
