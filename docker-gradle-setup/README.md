# AWS ECR Authenticate and Docker Login

## Requirements
On the top-level workflow, this actions needs permission to write the id-token.
```yaml
# These permissions are needed to interact with GitHub's OIDC Token endpoint.
permissions:
  id-token: write
  contents: read
```
