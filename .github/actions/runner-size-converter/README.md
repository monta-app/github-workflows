# Runner Size Converter Action

A composite action that converts a runner size into an arm64 GitHub runner name.

## Usage

```yaml
- name: Get runner name
  id: runner
  uses: monta-app/github-workflows/.github/actions/runner-size-converter@main
  with:
    runner-size: 'large'

- name: Use runner
  runs-on: ${{ steps.runner.outputs.runner-name }}
  steps:
    - run: echo "Running on ${{ steps.runner.outputs.runner-name }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `runner-size` | Yes | - | Runner size: `normal` or `large` |

## Outputs

| Output | Description |
|--------|-------------|
| `runner-name` | The converted runner name (e.g., `linux-arm64-xl`) |

## Runner Mapping

| Size | Output |
|------|--------|
| `normal` | `linux-arm64` |
| `large` | `linux-arm64-xl` |
