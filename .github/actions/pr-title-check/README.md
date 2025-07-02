# PR Title Check Action

A composite action that validates pull request titles against conventional commit standards.

## Usage

```yaml
- name: Check PR Title
  uses: monta-app/github-workflows/.github/actions/pr-title-check@main
```

## How it Works

This action uses [Slashgear/action-check-pr-title](https://github.com/Slashgear/action-check-pr-title) to validate PR titles against a conventional commit pattern.

## Title Format

PR titles must follow this pattern:
```
[optional-env] type(optional-scope): description
```

### Pattern Breakdown

- **Optional Environment Prefix**: `[develop]`, `[development]`, or `[staging]`
- **Type** (required): One of:
  - `build` - Changes that affect the build system
  - `chore` - Other changes that don't modify src or test files
  - `ci` - Changes to CI configuration files and scripts
  - `docs` - Documentation only changes
  - `feat` or `feature` - A new feature
  - `fix` - A bug fix
  - `perf` - A code change that improves performance
  - `refactor` - A code change that neither fixes a bug nor adds a feature
  - `revert` - Reverts a previous commit
  - `style` - Changes that do not affect the meaning of the code
  - `test` - Adding missing tests or correcting existing tests
  - `release` - Release commits
  - `ignore` - Changes to be ignored
- **Scope** (optional): Component name in parentheses
- **Breaking Change** (optional): `!` before the colon indicates breaking changes
- **Description** (required): Brief description of the change

## Valid Examples

- `feat: Add user authentication`
- `fix(api): Resolve null pointer exception`
- `feat(app-ui): Add new dashboard component (WEB-123)`
- `[staging] fix: Update database connection timeout`
- `refactor!: Change API response format`
- `docs(readme): Update installation instructions`

## Invalid Examples

- `Add new feature` (missing type)
- `feat Add authentication` (missing colon)
- `FEAT: Add feature` (type must be lowercase)
- `feat():Add feature` (missing space after colon)

## Example Workflow

```yaml
name: PR Validation
on:
  pull_request:
    types: [opened, edited, synchronize]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Check PR Title
        uses: monta-app/github-workflows/.github/actions/pr-title-check@main
```