variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "address_space" { type = list(string) }
variable "db_admin_login" { type = string }
variable "db_admin_password" { type = string, sensitive = true }
variable "db_app_password" { type = string, sensitive = true }
variable "image" { type = string }
variable "jwt_secret" { type = string, sensitive = true }
variable "min_replicas" { type = number, default = 1 }
variable "max_replicas" { type = number, default = 5 }
variable "tags" { type = map(string), default = {} }
