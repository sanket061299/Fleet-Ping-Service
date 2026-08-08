output "resource_group_name" { value = azurerm_resource_group.this.name }
output "container_registry_name" { value = azurerm_container_registry.this.name }
output "container_registry_login_server" { value = azurerm_container_registry.this.login_server }
output "container_app_name" { value = azurerm_container_app.api.name }
output "container_app_fqdn" { value = azurerm_container_app.api.ingress[0].fqdn }
output "migration_job_name" { value = azurerm_container_app_job.migration.name }
output "key_vault_name" { value = azurerm_key_vault.this.name }
output "postgres_server_name" { value = azurerm_postgresql_flexible_server.this.name }
