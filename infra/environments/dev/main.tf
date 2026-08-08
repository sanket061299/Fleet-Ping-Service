module "platform" {
  source = "../../modules/platform"

  name_prefix       = var.name_prefix
  environment       = "dev"
  location          = var.location
  address_space     = ["10.20.0.0/16"]
  db_admin_login    = var.db_admin_login
  db_admin_password = var.db_admin_password
  db_app_password   = var.db_app_password
  jwt_secret        = var.jwt_secret
  image             = var.image
  min_replicas      = 1
  max_replicas      = 3
  tags              = var.tags
}
