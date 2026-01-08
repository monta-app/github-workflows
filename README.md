# GitHub Workflows

This repository contains several reusable workflows designed to streamline the CI/CD process. The workflows aim to automate tasks such as testing, deployment, pull request management, and code quality checks.

## Available Workflows

### `backstage_techdocs.yml`
- **Purpose**: Manages the deployment of technical documentation using Backstage TechDocs.

### `it-test.yml`
- **Purpose**: Runs integration tests for ensuring code stability.

### `pull-request.yml`
- **Purpose**: Automates actions based on pull request events such as title validation, code coverage reports, and testing.

### `sonar-cloud.yml`
- **Purpose**: Integrates with SonarCloud for analyzing code quality and vulnerabilities.

### `semgrep-security-scan.yml`
- **Purpose**: Runs Semgrep static analysis to detect security vulnerabilities, hardcoded secrets, and unsafe coding patterns on pull requests.

### `deploy.yml`
- **Purpose**: Manages deployments to various environments based on the branch being deployed.

### `pull-request-kover.yml`
- **Purpose**: Manages the execution of Kover, a Kotlin coverage engine, for code coverage on pull requests.

### `monta-merge-command.yml`
- **Purpose**: Automates the process of merging pull requests and triggering subsequent deployment steps for `staging` and `production`.

### `release-tag.yml`
- **Purpose**: Automatically tags releases with a timestamped version.

### `staging-pr.yml`
- **Purpose**: Automatically creates a pull request to promote changes from `develop` to `staging`.

### `production-pr.yml`
- **Purpose**: Automatically creates a pull request for promoting changes to the `production` branch.

---

## Deployment Workflows

This repository provides two deployment patterns to support different Helm chart management strategies:

### Pattern 1: Kube-Manifests Pattern (Original)
Helm charts and deployment configurations are managed in the `kube-manifests` repository.

**Workflows:**
- `deploy-generic.yml` - Generic deployment workflow for any service
- `deploy-python.yml` - Python-specific deployment with testing
- `deploy-kotlin.yml` - Kotlin-specific deployment with Gradle testing

**Use when:** Your service's Helm charts live in the `kube-manifests` repository under `apps/{service-identifier}/{stage}/app/`.

### Pattern 2: Service-Repo Pattern (V2)
Helm charts are managed within each service's repository, enabling better service ownership.

**Workflows:**
- `deploy-generic-v2.yml` - Generic deployment workflow for service-repo pattern
- `component-deploy-v2.yml` - Low-level component that updates service repo charts

**Use when:** Your service manages its own Helm charts in `helm/{service-identifier}/{stage}/app/` within the service repository.

**Key differences:**
- Charts live in service repository instead of kube-manifests
- Deployment workflow updates service repo's `values.yaml` with image tags
- ArgoCD config in kube-manifests points to service repo for chart source
- ArgoCD tracks deployments directly from service repo commits (no cluster config updates needed)
- Better service ownership and versioning of deployment configurations

---

## How to Use

### 1. **Auto-create PR to Promote `develop` to `staging`**

This workflow is triggered by pushes to the `develop` branch. It automatically creates a pull request to promote changes to the `staging` branch using the `staging-pr.yml` workflow.

**Example**:
```yaml
name: Auto-create PR to promote develop to staging

on:
  push:
    branches:
      - develop

jobs:
  staging_pr:
    name: Pull request (Staging)
    uses: monta-app/github-workflows/.github/workflows/staging-pr.yml@v2
```

### 2. **Use workflows for release PR merging, production tagging and deployment**

This workflow listens for comments on pull requests and responds to specific commands.
It handles automatic PR merging, staging deployment, production pull request creation, tagging, and deployment based on the command `/monta-merge`.

**Example**:
```yaml
name: Release Workflow Automation
on:
  issue_comment:
    types:
      - created

jobs:
  monta-merge:
    name: auto-merge release pull request
    if: ${{ github.event.issue.pull_request && startsWith(github.event.comment.body, '/monta-merge') }}
    uses: monta-app/github-workflows/.github/workflows/monta-merge-command.yml@v2
    secrets: inherit

  trigger-staging-deploy:
    needs: monta-merge
    if: ${{ needs.monta-merge.outputs.base_branch == 'staging' }}
    # Update this to your deployment workflow, and ensure it runs on workflow_call
    uses: ./.github/workflows/deploy_staging.yml 
    secrets: inherit

  trigger-production-pr-creation:
    needs: monta-merge
    if: ${{ needs.monta-merge.outputs.base_branch == 'staging' }}
    uses: monta-app/github-workflows/.github/workflows/production-pr.yml@v2
    secrets: inherit

  trigger-production-tag-release:
    needs: monta-merge
    if: ${{ needs.monta-merge.outputs.base_branch == 'main' }}
    uses: monta-app/github-workflows/.github/workflows/release-tag.yml@v2
    secrets: inherit

  trigger-production-deploy:
    needs: trigger-production-tag-release
    # Update this to your deployment workflow, and ensure it runs on workflow_call
    uses: ./.github/workflows/deploy_production.yml
    if: ${{ needs.trigger-production-tag-release.outputs.tag_exists == 'false' }}
    secrets: inherit
```

### 3. **Deploy with Kube-Manifests Pattern**

Use this for services with Helm charts in the `kube-manifests` repository.

**Example**:
```yaml
name: Deploy Staging

on:
  push:
    tags:
      - '*'
  workflow_dispatch:

jobs:
  deploy:
    name: Deploy
    uses: monta-app/github-workflows/.github/workflows/deploy-generic.yml@main
    with:
      stage: "staging"
      service-name: "My Service"
      service-emoji: "🚀"
      service-identifier: my-service
      ecr-repository-name: my-service-staging
    secrets:
      AWS_ACCOUNT_ID: ${{ secrets.INTERNAL_AWS_ACCOUNT_ID }}
      MANIFEST_REPO_PAT: ${{ secrets.PAT }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

### 4. **Deploy with Service-Repo Pattern (V2)**

Use this for services that manage their own Helm charts in the service repository.

**Prerequisites:**
- Helm charts exist in your service repo (default location: `helm/{service-identifier}/{stage}/app/`)
- ArgoCD config in kube-manifests points to your service repo
- `values.yaml` includes `revision` and `build` fields under the image section

**Example:**
```yaml
name: Deploy Staging

on:
  push:
    tags:
      - '*'
  workflow_dispatch:

jobs:
  deploy:
    name: Deploy
    uses: monta-app/github-workflows/.github/workflows/deploy-generic-v2.yml@main
    with:
      stage: "staging"
      service-name: "My Service"
      service-emoji: "🚀"
      service-identifier: my-service
      ecr-repository-name: monta/my-service
      # helm-values-path: "helm/staging/app"  # Optional: override default (helm/{service-identifier}/{stage}/app)
    secrets:
      AWS_ACCOUNT_ID: ${{ secrets.INTERNAL_AWS_ACCOUNT_ID }}
      MANIFEST_REPO_PAT: ${{ secrets.PAT }}
      SLACK_APP_TOKEN: ${{ secrets.SLACK_APP_TOKEN }}
```

**values.yaml structure:**
```yaml
kotlin:  # or your chart type
  image:
    repository: 123456789.dkr.ecr.eu-west-1.amazonaws.com/monta/my-service
    tag: latest
    revision: "initial"  # Updated by workflow
    build: 0             # Updated by workflow
    pullPolicy: IfNotPresent
```

### 5. **Semgrep Security Scanning**

Run Semgrep static analysis on pull requests to detect security vulnerabilities before they reach production.

**Example (Kotlin/Java):**
```yaml
name: Security Scan

on:
  pull_request:
    branches: [main]

jobs:
  semgrep:
    name: Semgrep Security Scan
    uses: monta-app/github-workflows/.github/workflows/semgrep-security-scan.yml@main
    with:
      language: kotlin
    permissions:
      contents: read
      pull-requests: write
```

**Example (PHP):**
```yaml
name: Security Scan

on:
  pull_request:
    branches: [main]

jobs:
  semgrep:
    name: Semgrep Security Scan
    uses: monta-app/github-workflows/.github/workflows/semgrep-security-scan.yml@main
    with:
      language: php
    permissions:
      contents: read
      pull-requests: write
```

**Inputs:**
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `language` | Yes | - | Primary language: `kotlin`, `php`, or `generic` |
| `extra-configs` | No | `""` | Additional Semgrep config flags |
| `timeout-minutes` | No | `15` | Timeout for the scan job |
| `fail-on-high` | No | `true` | Whether to fail on high-severity findings |

**Language-specific rulesets:**
- **Kotlin**: `p/kotlin`, `p/java`, `r/kotlin.lang.security`, `r/java.lang.security`
- **PHP**: `p/php`, `r/php.lang.security`
- **All**: `p/security-audit`, `p/secrets`, `p/github-actions`, `p/docker`

## Contributing ##

If you are adding new workflows or updating existing ones, please ensure to update this `README` with descriptions and usage examples for easy integration by other teams. Make sure your workflows follow best practices for GitHub Actions to ensure reliability and maintainability.
