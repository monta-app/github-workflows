# Docker Compose Setup Action

A composite action that starts Docker Compose services and waits for all containers to become healthy.

## Usage

```yaml
- name: Setup Docker Compose
  uses: monta-app/github-workflows/.github/actions/docker-compose-setup@main
  with:
    docker-compose-path: './docker-compose.test.yml'
    timeout: '120'  # Optional, defaults to 60 seconds
    interval: '5'   # Optional, defaults to 2 seconds
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `docker-compose-path` | Yes | - | File path of the docker compose file |
| `timeout` | No | `60` | Timeout in seconds to wait for containers to be healthy |
| `interval` | No | `2` | Interval in seconds between health checks |

## How it Works

1. Starts Docker Compose services in detached mode
2. Polls container health status at the specified interval
3. Succeeds when all containers report as healthy
4. Fails if the timeout is reached before all containers are healthy

## Example

```yaml
name: Run Tests
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Start test services
        uses: monta-app/github-workflows/.github/actions/docker-compose-setup@main
        with:
          docker-compose-path: './docker-compose.test.yml'
          timeout: '90'
      
      - name: Run tests
        run: npm test
      
      - name: Cleanup
        if: always()
        run: docker compose -f ./docker-compose.test.yml down
```