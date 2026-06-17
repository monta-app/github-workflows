# Runner Size Converter Action

A composite action that converts a runner size into an arm64 GitHub runner name.
By default it resolves the self-hosted `linux-arm64` runners; set
`use-blacksmith-runners: true` to resolve the Blacksmith arm64 cloud runners
instead.

## Usage

```yaml
- name: Get runner name
  id: runner
  uses: monta-app/github-workflows/.github/actions/runner-size-converter@main
  with:
    runner-size: 'large'
    use-blacksmith-runners: false # optional, defaults to false

- name: Use runner
  runs-on: ${{ steps.runner.outputs.runner-name }}
  steps:
    - run: echo "Running on ${{ steps.runner.outputs.runner-name }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | Yes | - | Runner size: `normal` or `large` |
| `use-blacksmith-runners` | No | `false` | Resolve Blacksmith arm64 cloud runners instead of the self-hosted `linux-arm64` runners |

## Outputs

| Output | Description |
|--------|-------------|
| `runner-name` | The converted runner name (e.g., `linux-arm64-xl`) |

## Runner Mapping

| Size | `use-blacksmith-runners` | Output |
|------|--------------------------|--------|
| `normal` | `false` | `linux-arm64` |
| `large` | `false` | `linux-arm64-xl` |
| `normal` | `true` | `blacksmith-4vcpu-ubuntu-2404-arm` |
| `large` | `true` | `blacksmith-16vcpu-ubuntu-2404-arm` |
