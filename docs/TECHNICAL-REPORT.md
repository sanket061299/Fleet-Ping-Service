# VexarDrive Technologies — DevOps & Cloud Infrastructure Assessment

## 1. Executive summary

The inherited service was functional as a demo but was not safe to operate as a production service. The highest-risk findings were hard-coded database credentials, a hard-coded JWT secret, SQL injection in the login endpoint, a completely unauthenticated admin endpoint, one database connection per request, no health/readiness contract, no real tests, a root container using `node:latest`, exposed PostgreSQL in Docker Compose, and a CI workflow that pushed a mutable `latest` image using static registry credentials.

The proposed target state uses Azure Container Apps, Azure Database for PostgreSQL Flexible Server with private networking, Azure Key Vault, managed identities, Azure Container Registry, Terraform, GitHub Actions OIDC, and Azure Monitor/Log Analytics.

## 2. Initial assessment

### Critical

| Finding | Risk | Change |
|---|---|---|
| Hard-coded PostgreSQL password in `server.js` and Compose | Credential compromise | Removed; secrets come from Key Vault/environment |
| Hard-coded JWT secret | Token forgery | Removed; secret is injected at runtime |
| SQL built with `phone` interpolation | SQL injection | Parameterized query |
| `/api/admin/drivers` has no authentication | Data exposure | Bearer JWT + admin role check |
| OTP is accepted but never verified | Authentication bypass | Added `otp_hash` and scrypt verification |

### High

| Finding | Risk | Change |
|---|---|---|
| New PostgreSQL client for every request | Connection exhaustion/latency | `pg.Pool` with bounded connections |
| No health/readiness endpoints | Bad deployments and slow recovery | `/healthz` and `/readyz` |
| `node:latest` | Unpredictable builds | Node 22 pinned major line |
| Container runs as root | Larger blast radius | Non-root UID/GID |
| Docker build copies everything | Large/dirty image | `.dockerignore`, production-only install |
| `npm install` at runtime image build without lock | Reproducibility weakness | Dependency versions pinned; next hardening step is committing lockfile |
| PostgreSQL bound to `0.0.0.0` in Compose | Unnecessary exposure | Database is only reachable by app network |

### Medium

- No request validation: added bounds for vehicle ID, coordinates, speed and timestamp.
- Long JWT lifetime: reduced to 15 minutes.
- No structured logs: added JSON logs.
- No graceful shutdown: added SIGTERM/SIGINT handling.
- No database indexes for common fleet-ping access patterns: added vehicle/time indexes.
- No tests: added Node built-in test coverage for health, readiness, validation and admin access.

## 3. Containerization

The runtime image is based on Node 22 Debian slim. The application runs as an unprivileged user, exposes only TCP/3000, uses a health check, supports graceful SIGTERM handling, and receives all environment-specific configuration at runtime.

The image is tagged using the Git commit SHA rather than `latest`. This makes every deployment traceable and gives the release process a stable rollback target.

A further hardening step for a real repository would be committing `package-lock.json` and using `npm ci --omit=dev`.

## 4. Azure architecture

### Compute

Azure Container Apps is preferred over AKS because the service is a small stateless HTTP API. AKS would introduce cluster lifecycle, node pools, upgrades, ingress, CNI, policy, and other operational responsibilities that are not justified by the current workload.

Container Apps provides revisions and autoscaling without requiring a Kubernetes control plane operated by the team.

### Database

Azure Database for PostgreSQL Flexible Server is private to the VNet. The application does not receive database credentials through source code. PostgreSQL uses automated backups and point-in-time restore.

The application uses a connection pool and bounded maximum connections. At scale, the pool size and number of replicas must be calculated against the PostgreSQL connection budget.

## 5. Networking

The VNet contains:

```text
Internet
   |
   v
Azure Container Apps public HTTPS ingress
   |
   v
Container Apps environment
   |
   +---- private DNS ----> PostgreSQL Flexible Server
   |
   +---- private DNS ----> Key Vault / private services as required
```

The API ingress is public because vehicles must reach it. PostgreSQL is not publicly reachable. Key Vault is protected with Azure RBAC and can be private-endpoint enabled when the environment/compliance profile requires it.

Network security groups and subnet delegation are used so the application environment and PostgreSQL have clear boundaries.

## 6. Identity and secrets

GitHub Actions authenticates to Azure using OIDC/federated identity instead of a long-lived client secret.

The runtime identity is a user-assigned managed identity. It receives only:

- `AcrPull` on ACR
- `Key Vault Secrets User` on the application vault

Terraform uses a separate deployment identity with the permissions required to manage the infrastructure.

No application credential is committed to Git.

## 7. CI/CD

The pipeline is intentionally staged:

```text
Pull Request
   |
   +--> syntax/tests
   +--> dependency audit
   +--> secret scan
   +--> Terraform fmt/validate
   +--> Docker build
   +--> image vulnerability scan
   |
main/develop
   |
   v
Build immutable image
   |
   v
Push SHA tag to ACR
   |
   v
Terraform plan/apply
   |
   v
Run DB migration job inside VNet
   |
   v
Deploy new Container Apps revision
   |
   v
Health + readiness + smoke test
   |
   +--> success -> release
   |
   +--> failure -> rollback revision
```

Production should be a protected GitHub Environment requiring an approval before the deployment job executes.

## 8. Database migrations

Schema changes should follow an expand/migrate/contract approach.

Example:

1. Add a nullable/new column.
2. Deploy application code that can work with both old and new schema.
3. Backfill data.
4. Enforce constraints.
5. Remove obsolete fields in a later release.

Migration execution is isolated from application startup. A Container Apps Job runs the migration inside the same private network as PostgreSQL, avoiding a public database firewall exception for the GitHub runner.

## 9. Backup and recovery

Azure Database for PostgreSQL Flexible Server automatically performs backups and supports point-in-time recovery. The initial configuration uses a 14-day retention window; production policy can increase this up to the organization's required retention.

Recovery should be tested, not just configured. A quarterly restore drill should verify:

- RPO/RTO
- restored application connectivity
- schema consistency
- data integrity
- operational runbook correctness

For larger business continuity requirements, add geo-redundant backup/restore and a secondary-region architecture.

## 10. Observability

### Health

- `/healthz`: process-level liveness; no dependency calls.
- `/readyz`: verifies database connectivity.

### Logs

JSON logs include:

- timestamp
- level
- event
- HTTP method
- path
- status
- duration
- error message

No passwords, JWTs, OTPs, or database connection strings are logged.

### Alerts

| Alert | Example trigger | Why |
|---|---|---|
| HTTP 5xx | >5% for 5 minutes | User-facing failure |
| Latency | p95 > 1s for 5 minutes | API degradation |
| Unhealthy replicas | any replica repeatedly failing | Deployment/runtime issue |
| DB CPU | >80% for 10 minutes | Capacity pressure |
| DB connections | >80% of configured limit | Pool/scale risk |
| DB storage | >80% | Risk of write failure |
| Failed migration | any non-zero migration job | Release blocker |
| Container restart | repeated restarts | Crash loop/resource problem |

## 11. Scaling fleet pings

Fleet pings are write-heavy. As the fleet grows:

- increase Container Apps replicas based on concurrent requests/CPU
- use connection pooling carefully
- batch inserts where the ingestion contract permits it
- partition `fleet_pings` by time or vehicle when table size becomes large
- move analytics queries away from the transactional database
- introduce a durable event ingestion layer only when measured traffic justifies it
- consider TimescaleDB-compatible/time-series architecture if PostgreSQL time-series workloads become dominant

The important point is to avoid introducing Kafka/Redis/service mesh prematurely.

## 12. Reliability and rollback

Application revisions are immutable and image tags are immutable SHA references.

A failed release is handled by:

1. Detect failed health/readiness/smoke checks.
2. Mark the deployment failed.
3. Shift traffic back to the previous healthy revision.
4. Preserve the failed revision for diagnosis.
5. Investigate logs and metrics.
6. Fix forward or redeploy the previous known-good image.

Database rollback is different from application rollback. A schema migration must be backward compatible so an application rollback does not immediately break against the newer schema.

## 13. Cost considerations

The design avoids unnecessary infrastructure:

- no AKS
- no self-managed VM cluster
- no Redis initially
- no service mesh
- no dedicated NAT gateway unless outbound control becomes necessary
- consumption-based Container Apps for early workloads

The main cost drivers will be PostgreSQL compute/storage, Container Apps usage, Log Analytics ingestion, ACR storage, and networking/private endpoints.

## 14. What was not changed

I did not add Kubernetes, Redis, Kafka, API Management, or a full service mesh because there is no evidence in the starter service that the complexity is currently justified.

I also did not implement a complete OTP delivery provider because the assessment does not provide an SMS/OTP vendor, phone verification workflow, or secret-management contract. The application now verifies a stored OTP hash rather than silently ignoring the OTP field.

## 15. Known limitations

- A live Azure subscription was not required, so deployment is designed as IaC but should be validated in an actual subscription before production.
- The final repository should commit a generated `package-lock.json` after dependency installation.
- API authentication/authorization should eventually use a dedicated identity provider rather than a minimal JWT implementation.
- Fleet ingestion should eventually use an idempotency key to protect against device retries and duplicate pings.
- Rate limiting should be enforced at the edge/gateway as fleet traffic grows.
- Application metrics can be expanded with OpenTelemetry/Application Insights after baseline operations are established.

## 16. AI usage

AI was used for repository review, security-risk identification, Terraform/CI/CD scaffolding, documentation drafting, and implementation assistance. The submitted implementation must be reviewed, tested, and understood by the candidate before submission.
