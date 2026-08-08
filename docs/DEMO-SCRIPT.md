# 5–7 minute demo video script

## 1. Repository review
Show the starter findings:
- hard-coded credentials
- SQL injection
- unauthenticated admin endpoint
- per-request DB connections
- mutable `latest` image
- weak Dockerfile
- minimal deployment workflow

## 2. Application
Run:

```bash
docker compose up --build -d
curl http://localhost:3000/healthz
curl http://localhost:3000/readyz
```

Show the non-root container:

```bash
docker compose exec app id
```

Show validation and tests:

```bash
npm test
npm run lint
```

## 3. Terraform
Open `infra/modules/platform/main.tf` and explain:
- VNet
- private PostgreSQL
- Key Vault
- managed identity
- ACR
- Container Apps
- migration job
- Log Analytics

## 4. CI/CD
Open `.github/workflows/ci.yml` and `.github/workflows/deploy.yml`.

Explain the sequence:

Test → Build → Scan → Push SHA image → Terraform → Migration → Deploy → Verify → Rollback.

## 5. Security
Show that no credentials exist in `server.js`.

Explain:
- GitHub OIDC
- managed identity
- Key Vault
- private PostgreSQL
- ACR pull without registry password

## 6. Trade-offs
Explain why Container Apps was selected instead of AKS and why Redis/Kafka/service mesh were intentionally not added.

## 7. Close
Mention that a live Azure deployment was not required and that the Terraform is structured for a real deployment with remote state and protected GitHub environments.
