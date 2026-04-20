variable "subnet_ids" {
  description = "Subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for Redis"
  type        = string
}
