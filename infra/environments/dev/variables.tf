variable "name_prefix" { type = string, default = "vexarfleet" }
variable "location" { type = string, default = "Central India" }
variable "db_admin_login" { type = string, default = "vexaradmin" }
variable "db_admin_password" { type = string, sensitive = true }
variable "db_app_password" { type = string, sensitive = true }
variable "jwt_secret" { type = string, sensitive = true }
variable "image" { type = string }
variable "tags" { type = map(string), default = { workload = "fleet-ping", managed_by = "terraform" } }
