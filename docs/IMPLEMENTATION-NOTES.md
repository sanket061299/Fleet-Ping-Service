# Implementation notes

## One important improvement before submission

Run:

```bash
npm install
npm test
npm audit --audit-level=high
```

and commit the generated `package-lock.json`. Then change the Dockerfile and workflows from `npm install` to `npm ci`.

## Terraform bootstrap

The assessment does not require a live Azure subscription. If you have one:

1. Create an Azure Storage account and blob container for Terraform state.
2. Configure GitHub OIDC federation for the deployment identity.
3. Add the `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` variables to the GitHub environments.
4. Add `DB_ADMIN_PASSWORD`, `DB_APP_PASSWORD`, and `JWT_SECRET` as environment secrets.
5. Initialize the backend in the environment directory.
6. Run the Terraform workflow.
7. Run the deploy workflow.

## Production hardening

For a real production launch, I would also:

- enable Key Vault private endpoint and private DNS
- configure Azure Monitor alerts as code
- enable zone redundancy where the region/SKU supports it
- configure ACR retention and image signing/attestation
- add API edge rate limiting/WAF
- add OpenTelemetry tracing
- add an idempotency key for fleet pings
- commit and enforce `package-lock.json`
- add dependency update automation
- perform a PostgreSQL restore drill
