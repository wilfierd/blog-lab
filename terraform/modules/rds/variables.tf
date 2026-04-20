variable "db_username" {
  description = "Master username for PostgreSQL"
  type        = string
}

variable "db_password" {
  description = "Master password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_subnet_ids" {
  description = "Private DB subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for RDS"
  type        = string
}
