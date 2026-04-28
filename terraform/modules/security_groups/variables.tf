variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — restricts Prometheus/Alertmanager to internal access only"
  type        = string
}
