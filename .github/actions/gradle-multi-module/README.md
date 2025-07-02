# Gradle Multi-Module Command Runner Action

A composite action that runs Gradle tasks with automatic module-specific targeting for multi-module projects.

## Usage

### For root project tasks
```yaml
- name: Run Gradle build
  uses: monta-app/github-workflows/.github/actions/gradle-multi-module@main
  with:
    gradle-tasks: 'clean build'
    gradle-args: '--no-daemon --parallel'  # Optional, these are the defaults
```

### For module-specific tasks
```yaml
- name: Run tests in specific module
  uses: monta-app/github-workflows/.github/actions/gradle-multi-module@main
  with:
    gradle-module: 'service-api'
    gradle-tasks: 'test integrationTest'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `gradle-module` | No | - | Name of the gradle module (leave empty for root project) |
| `gradle-tasks` | Yes | - | Space-separated list of Gradle tasks to run |
| `gradle-args` | No | `--no-daemon --parallel` | Additional Gradle arguments |

## How it Works

1. **Root Project**: When no module is specified, runs tasks directly on the root project
2. **Module-Specific**: When a module is specified, automatically prefixes each task with the module name
   - Example: `gradle-module: 'api'` with `gradle-tasks: 'test build'` 
   - Results in: `./gradlew :api:test :api:build`

## Examples

### Multi-module project with different tasks per module
```yaml
name: Build and Test
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Build all modules
        uses: monta-app/github-workflows/.github/actions/gradle-multi-module@main
        with:
          gradle-tasks: 'clean build'
      
      - name: Run API module tests
        uses: monta-app/github-workflows/.github/actions/gradle-multi-module@main
        with:
          gradle-module: 'api'
          gradle-tasks: 'test integrationTest'
      
      - name: Run Service module tests
        uses: monta-app/github-workflows/.github/actions/gradle-multi-module@main
        with:
          gradle-module: 'service'
          gradle-tasks: 'test'
          gradle-args: '--no-daemon --parallel --info'
```