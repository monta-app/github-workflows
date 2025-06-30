# Claude Code Notes

## Last Documentation Update
- **Date**: 2025-06-29
- **Latest SHA**: 95e2ba8646d899376775e598f696499a9860def9
- **Changes**: Created reusable Docker Compose composite action and integrated it across workflows

## Recent Workflow Changes (2025-06-29)
1. **Docker Compose Composite Action**: Created `.github/actions/docker-compose-setup` for reusable Docker Compose setup
2. **Workflow Updates**: Integrated Docker Compose action in `pull-request-bun.yml`, `component-test-python.yml`, and `deploy-python.yml`
3. **Documentation**: Updated workflow guide to document Docker Compose support

## Previous Changes (2025-06-21)
1. **Code Coverage**: Added LCOV coverage reporting to pull-request-bun workflow
2. **Docker Compose**: Added optional Docker Compose support for test services
3. **System Fixes**: Resolved man-db interactive prompts with debconf configuration
4. **Package Installation**: Added `-y` flags to apt install commands

When updating documentation next time, check commits since SHA: 95e2ba8646d899376775e598f696499a9860def9
