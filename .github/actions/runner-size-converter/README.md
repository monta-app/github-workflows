# Runner Size Converter Action

A composite action that converts a runner size into an arm64 GitHub runner name.
With `use-arc-runners: true` it resolves the self-hosted ARC runners; otherwise
it resolves the GitHub-hosted `linux-arm64` larger runners.

## Usage

```yaml
- name: Get runner name
  id: runner
  uses: monta-app/github-workflows/.github/actions/runner-size-converter@main
  with:
    runner-size: 'large'
    use-arc-runners: true # optional, defaults to false

- name: Use runner
  runs-on: ${{ steps.runner.outputs.runner-name }}
  steps:
    - run: echo "Running on ${{ steps.runner.outputs.runner-name }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | Yes | - | Runner size: `normal` or `large` |
| `use-arc-runners` | No | `false` | Resolve the self-hosted ARC arm64 runners (private repositories only). Otherwise the GitHub-hosted `linux-arm64` runners |

## Outputs

| Output | Description |
|--------|-------------|
| `runner-name` | The converted runner name (e.g., `arc-arm64-4cpu-12gb`) |

## Runner Mapping

| Size | `use-arc-runners` | Output |
|------|-------------------|--------|
| `normal` | `false` | `linux-arm64` |
| `large` | `false` | `linux-arm64-xl` |
| `normal` | `true` | `arc-arm64-4cpu-12gb` |
| `large` | `true` | `arc-arm64-8cpu-24gb` |

In a public repository (`github.event.repository.private == false`) the output is always `ubuntu-24.04-arm`, GitHub's standard arm64 runner, whatever the inputs. ARC is only used in private repositories; when the event has no repository (e.g. `schedule`), the table above applies without ARC.
