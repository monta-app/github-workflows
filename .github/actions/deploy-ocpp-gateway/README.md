# Deploy OCPP Gateway Action

A composite action that deploys OCPP Gateway services to the Infra Portal.

## Usage

```yaml
- name: Deploy OCPP Gateway
  uses: monta-app/github-workflows/.github/actions/deploy-ocpp-gateway@main
  with:
    service-identifier: 'ocpp-gateway'
    stage: 'staging'
    ocpp-gateway-replicas: '3'
    aws-account-id: ${{ secrets.AWS_ACCOUNT_ID }}
    infra-portal-token: ${{ secrets.INFRA_PORTAL_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `service-identifier` | Yes | - | Identifier of the service being released (e.g., ocpp-gateway) |
| `stage` | Yes | - | Stage being released (dev, staging, production) |
| `ocpp-gateway-replicas` | Yes | - | Number of replicas for OCPP Gateway |
| `aws-account-id` | Yes | - | AWS account ID |
| `infra-portal-token` | Yes | - | Infra Portal authentication token |

## How it Works

1. Determines the appropriate Infra Portal hostname based on the stage:
   - For `dev` and `staging`: Uses `infra-portal.staging.monta.app`
   - For `production`: Uses `infra-portal.monta.app`

2. Determines the cluster based on the stage:
   - For `dev` and `staging`: Uses `staging` cluster
   - For `production`: Uses `production` cluster

3. Makes a POST request to the Infra Portal to create a gateway release with:
   - Commit hash from the current GitHub context
   - Build number from the GitHub run number
   - AWS account ID
   - Number of replicas

4. Fails the action if the response is not 200 OK

## Example

```yaml
name: Deploy OCPP Gateway
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to Staging
        uses: monta-app/github-workflows/.github/actions/deploy-ocpp-gateway@main
        with:
          service-identifier: 'ocpp-gateway'
          stage: 'staging'
          ocpp-gateway-replicas: '3'
          aws-account-id: ${{ secrets.AWS_ACCOUNT_ID }}
          infra-portal-token: ${{ secrets.INFRA_PORTAL_TOKEN }}
```