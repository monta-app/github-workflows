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

## Contributing ##

If you are adding new workflows or updating existing ones, please ensure to update this `README` with descriptions and usage examples for easy integration by other teams. Make sure your workflows follow best practices for GitHub Actions to ensure reliability and maintainability.
