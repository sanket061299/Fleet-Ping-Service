# START HERE

## What has been completed

This solution covers the assessment deliverables:

1. Application review and remediation
2. Production containerization
3. Terraform Azure infrastructure
4. GitHub Actions CI/CD
5. PostgreSQL operational strategy
6. Key Vault + managed identity + RBAC
7. Health/readiness/structured logging
8. Architecture diagram
9. Technical report
10. Demo video script

## Important before submission

This is an assessment solution scaffold, not a claim that Azure resources were actually deployed.

Before submitting:

1. Fork the starter repository.
2. Copy these files into the fork.
3. Run `npm install` and commit `package-lock.json`.
4. Run `npm test`.
5. Run `npm audit --audit-level=high`.
6. Install Terraform and run `terraform fmt -recursive`.
7. Create a secure remote Terraform state backend.
8. Configure GitHub OIDC.
9. Configure the GitHub `dev` and `production` environments.
10. If you have Azure access, deploy `dev` first.
11. Record a short demo showing the code, Terraform, workflow and verification.
12. Submit the GitHub link, report, architecture diagram and demo link.

## Do not do this

- Do not commit `.env`.
- Do not commit Terraform state.
- Do not reuse the credentials from the starter repository.
- Do not create long-lived Azure client secrets for GitHub Actions.
- Do not use `latest` as the release identifier.
