variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance"
  type        = string
  sensitive   = true
}
