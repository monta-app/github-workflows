# Runner Size Converter Action

A composite action that converts a runner size into an arm64 GitHub runner name.
By default it resolves the Blacksmith arm64 cloud runners; set
`use-blacksmith-runners: false` to resolve the self-hosted `linux-arm64` runners
instead, or `use-arc-runners: true` to resolve the self-hosted ARC runners
(this takes precedence).

## Usage

```yaml
- name: Get runner name
  id: runner
  uses: monta-app/github-workflows/.github/actions/runner-size-converter@main
  with:
    runner-size: 'large'
    use-blacksmith-runners: true # optional, defaults to true
    use-arc-runners: false # optional, defaults to false; wins over use-blacksmith-runners

- name: Use runner
  runs-on: ${{ steps.runner.outputs.runner-name }}
  steps:
    - run: echo "Running on ${{ steps.runner.outputs.runner-name }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | Yes | - | Runner size: `normal` or `large` |
| `use-blacksmith-runners` | No | `true` | Resolve Blacksmith arm64 cloud runners (default). Set to `false` to resolve the self-hosted `linux-arm64` runners |
| `use-arc-runners` | No | `false` | Resolve the self-hosted ARC arm64 runners. Takes precedence over `use-blacksmith-runners` |

## Outputs

| Output | Description |
|--------|-------------|
| `runner-name` | The converted runner name (e.g., `linux-arm64-xl`) |

## Runner Mapping

| Size | `use-arc-runners` | `use-blacksmith-runners` | Output |
|------|-------------------|--------------------------|--------|
| `normal` | `false` | `false` | `linux-arm64` |
| `large` | `false` | `false` | `linux-arm64-xl` |
| `normal` | `false` | `true` | `blacksmith-4vcpu-ubuntu-2404-arm` |
| `large` | `false` | `true` | `blacksmith-16vcpu-ubuntu-2404-arm` |
| `normal` | `true` | any | `arc-arm64-4cpu-12gb` |
| `large` | `true` | any | `arc-arm64-8cpu-24gb` |

In a public repository (`github.event.repository.private == false`) the output is always `ubuntu-24.04-arm`, GitHub's standard arm64 runner, whatever the inputs. ARC is only used in private repositories; when the event has no repository (e.g. `schedule`), the table above applies without ARC.
