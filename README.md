# VexarDrive Fleet Ping Service — Production Assessment Solution

This repository is an implementation of the VexarDrive DevOps & Cloud Infrastructure Engineer assessment.

## Chosen architecture

- **Compute:** Azure Container Apps
- **Registry:** Azure Container Registry
- **Database:** Azure Database for PostgreSQL Flexible Server
- **Secrets:** Azure Key Vault with RBAC
- **Identity:** User-assigned managed identities for workload access
- **Network:** Dedicated Azure VNet; Container Apps environment and PostgreSQL use private networking
- **Observability:** Log Analytics + Azure Monitor
- **IaC:** Terraform
- **CI/CD:** GitHub Actions + Azure OIDC
- **Deployment model:** immutable image tags based on Git SHA, Container Apps revisions, environment approvals

Container Apps was selected instead of AKS because this service is a small stateless HTTP API and does not need Kubernetes-specific orchestration. It provides autoscaling and revisions with substantially less operational overhead.

## Repository layout

```text
.
├── .github/workflows/
│   ├── ci.yml
│   ├── terraform.yml
│   └── deploy.yml
├── infra/
│   ├── modules/platform/
│   └── environments/
│       ├── dev/
│       └── prod/
├── migrations/
├── scripts/
├── tests/
├── docs/
├── Dockerfile
├── docker-compose.yml
├── schema.sql
├── server.js
└── package.json
```

## Local run

```bash
docker compose up --build
curl http://localhost:3000/healthz
curl http://localhost:3000/readyz
```

## CI/CD

Pull requests run validation and security checks. The deployment pipeline:

1. Test
2. Build
3. Dependency/image security scan
4. Push immutable image to ACR
5. Deploy infrastructure (Terraform)
6. Run database migration job inside the VNet
7. Deploy Container Apps revision
8. Verify `/healthz` and `/readyz`
9. Smoke-test the API
10. Roll back to the previous revision if verification fails

`main` is the production path and should be protected with required reviews and the GitHub `production` environment approval gate.

## Required GitHub configuration

Create GitHub environments named `dev` and `production`.

Configure OIDC variables/secrets as appropriate:

- `DB_ADMIN_PASSWORD`
- `DB_APP_PASSWORD`
- `JWT_SECRET`

Prefer GitHub Actions OIDC over long-lived Azure client secrets.

For the Terraform backend, create an Azure Storage account/container outside the application stack or use your organization's existing remote backend. Never commit Terraform state.

## Important assessment note

The starter repository contains real-looking hard-coded credentials. They must be treated as compromised and rotated/revoked. Do not copy them into the new implementation.

The starter also has no real OTP verification model. This solution adds an `otp_hash` field and verifies OTPs using scrypt. A production system would additionally integrate with the organization's OTP issuance/delivery service and add brute-force protection.

## Deployment environments

- `dev`: automatic deployment after CI succeeds on `develop`
- `prod`: deployment from `main`, protected by GitHub environment approval
- Environment-specific Terraform variables live in each environment directory and are not secrets.
- Secrets are stored in Key Vault and referenced by Container Apps through managed identity.

## Rollback

Container Apps revisions are immutable. If a deployment fails its smoke tests, the workflow restores the previous revision. The image remains available in ACR by immutable SHA tag.

Database migrations are designed to be backward-compatible before application rollout. Destructive schema changes require a separate migration process.

## Cost

The design deliberately avoids AKS, a NAT gateway, Redis, a service mesh, and unnecessary private endpoints for the first production stage. Those can be introduced when traffic or compliance requirements justify them.

## AI usage

AI assistance was used to review the starter repository, identify production risks, draft implementation patterns, and improve documentation. All generated code should be reviewed and validated by the candidate before submission.
