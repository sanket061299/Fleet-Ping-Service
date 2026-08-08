# Architecture

```mermaid
flowchart LR
    V[Vehicle / Driver Clients]
    GH[GitHub Repository]
    GA[GitHub Actions]
    OIDC[Azure OIDC / Federated Identity]
    ACR[Azure Container Registry]
    TF[Terraform]
    VNET[Azure VNet]
    ACA[Azure Container Apps Environment]
    APP[Fleet Ping API]
    JOB[Container Apps Migration Job]
    KV[Azure Key Vault]
    PG[Azure Database for PostgreSQL Flexible Server]
    LA[Log Analytics / Azure Monitor]

    V -->|HTTPS| ACA
    ACA --> APP
    APP -->|private TCP 5432| PG
    APP -->|managed identity| KV
    JOB -->|private TCP 5432| PG
    JOB -->|managed identity| KV

    GH --> GA
    GA -->|OIDC| OIDC
    GA -->|push immutable SHA image| ACR
    GA -->|Terraform apply| TF
    TF --> VNET
    TF --> ACA
    TF --> PG
    TF --> KV
    TF --> LA
    GA -->|start migration job| JOB
    GA -->|deploy revision| APP

    ACA --> LA
    APP -->|structured logs| LA
    PG --> LA
```

## Network boundaries

- Public: HTTPS API ingress only.
- Private: PostgreSQL and internal infrastructure.
- Identity: managed identities rather than application-held Azure credentials.
- CI/CD: GitHub OIDC with no long-lived Azure secret.
