# Runner Size Converter Action

A composite action that converts runner size and architecture inputs into GitHub runner names.

## Usage

```yaml
- name: Get runner name
  id: runner
  uses: monta-app/github-workflows/.github/actions/runner-size-converter@main
  with:
    runner-size: 'large'
    architecture: 'arm64'  # Optional, defaults to 'x64'

- name: Use runner
  runs-on: ${{ steps.runner.outputs.runner-name }}
  steps:
    - run: echo "Running on ${{ steps.runner.outputs.runner-name }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | Yes | - | Runner size: `normal` or `large` |
| `architecture` | No | `x64` | Runner architecture: `x64` or `arm64` |

## Outputs

| Output | Description |
|--------|-------------|
| `runner-name` | The converted runner name (e.g., `linux-x64-xl`) |

## Runner Mapping

| Size | Architecture | Output |
|------|--------------|--------|
| `normal` | `x64` | `linux-x64` |
| `large` | `x64` | `linux-x64-xl` |
| `normal` | `arm64` | `linux-arm64` |
| `large` | `arm64` | `linux-arm64-xl` |
