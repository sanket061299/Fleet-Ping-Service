terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-${var.environment}-logs"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-${var.environment}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.20.0.0/23"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.20.2.0/24"]

  delegation {
    name = "postgres-flexible-server"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name_prefix}-${var.environment}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
  resource_group_name   = azurerm_resource_group.this.name
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "${var.name_prefix}-${var.environment}-pg"
  resource_group_name    = azurerm_resource_group.this.name
  location               = var.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login    = var.db_admin_login
  administrator_password = var.db_admin_password
  storage_mb             = 32768
  storage_auto_grow_enabled = true
  sku_name               = "B_Standard_B1ms"
  backup_retention_days  = 14
  tags                   = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "fleet" {
  name      = "vexar_fleet"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_container_registry" "this" {
  name                = replace("${var.name_prefix}${var.environment}acr", "-", "")
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "runtime" {
  name                = "${var.name_prefix}-${var.environment}-runtime"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
}

resource "azurerm_key_vault" "this" {
  name                       = substr(replace("${var.name_prefix}${var.environment}kv", "-", ""), 0, 24)
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  enable_rbac_authorization  = true
  public_network_access_enabled = true
  tags                       = var.tags
}

resource "azurerm_key_vault_secret" "db_app_password" {
  name         = "db-app-password"
  value        = var.db_app_password
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "db_admin_password" {
  name         = "db-admin-password"
  value        = var.db_admin_password
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = "database-url"
  value        = "postgresql://appuser:${urlencode(var.db_app_password)}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/vexar_fleet?sslmode=require"
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = var.jwt_secret
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_role_assignment" "runtime_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
}

resource "azurerm_container_app_environment" "this" {
  name                         = "${var.name_prefix}-${var.environment}-cae"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this.name
  infrastructure_subnet_id    = azurerm_subnet.aca.id
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.this.id
  logs_destination             = "log-analytics"
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  tags = var.tags
}

resource "azurerm_container_app" "api" {
  name                         = "${var.name_prefix}-${var.environment}-api"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Multiple"
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runtime.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.runtime.id
  }

  secret {
    name                = "database-url"
    key_vault_secret_id = azurerm_key_vault_secret.db_app_password.versionless_id
    identity            = azurerm_user_assigned_identity.runtime.id
  }

  secret {
    name                = "jwt-secret"
    key_vault_secret_id = azurerm_key_vault_secret.jwt_secret.versionless_id
    identity            = azurerm_user_assigned_identity.runtime.id
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "api"
      image  = var.image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }
      env {
        name  = "DB_SSL"
        value = "true"
      }
      env {
        name  = "DB_POOL_MAX"
        value = "20"
      }

      startup_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/healthz"
        initial_delay = 5
        interval_seconds = 5
        failure_count_threshold = 10
      }

      readiness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/readyz"
        interval_seconds = 10
        failure_count_threshold = 3
      }

      liveness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/healthz"
        interval_seconds = 30
        failure_count_threshold = 3
      }
    }

    http_scale_rule {
      name = "http"
      concurrent_requests = 50
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.runtime_kv
  ]
}

resource "azurerm_container_app_job" "migration" {
  name                         = "${var.name_prefix}-${var.environment}-migration"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  replica_timeout_in_seconds   = 300
  replica_retry_limit          = 1

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runtime.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.runtime.id
  }

  secret {
    name                = "db-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.db_admin_password.versionless_id
    identity            = azurerm_user_assigned_identity.runtime.id
  }

  secret {
    name                = "db-app-password"
    key_vault_secret_id = azurerm_key_vault_secret.db_app_password.versionless_id
    identity            = azurerm_user_assigned_identity.runtime.id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "migration"
      image  = var.image
      cpu    = 0.25
      memory = "0.5Gi"
      command = ["node"]
      args = ["scripts/migrate.js"]

      env {
        name  = "DATABASE_HOST"
        value = azurerm_postgresql_flexible_server.this.fqdn
      }
      env {
        name  = "DATABASE_NAME"
        value = "vexar_fleet"
      }
      env {
        name  = "DATABASE_ADMIN"
        value = var.db_admin_login
      }
      env {
        name        = "DATABASE_ADMIN_PASSWORD"
        secret_name = "db-admin-password"
      }
      env {
        name        = "DATABASE_APP_PASSWORD"
        secret_name = "db-app-password"
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.runtime_kv,
    azurerm_postgresql_flexible_server_database.fleet
  ]

  tags = var.tags
}
