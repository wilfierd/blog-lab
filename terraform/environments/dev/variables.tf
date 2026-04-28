variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_a" {
  description = "Primary availability zone"
  type        = string
  default     = "us-west-2a"
}

variable "az_b" {
  description = "Secondary availability zone"
  type        = string
  default     = "us-west-2b"
}

variable "db_username" {
  description = "Master username for PostgreSQL RDS"
  type        = string
  default     = "admins"
}

variable "db_password" {
  description = "Master password for PostgreSQL RDS"
  type        = string
  sensitive   = true
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}

variable "google_redirect_url" {
  description = "Google OAuth redirect URL"
  type        = string
  default     = "https://blog.wilfierd.engineer/auth/google/callback"
}

variable "grafana_password" {
  description = "Grafana admin password for the monitoring EC2"
  type        = string
  sensitive   = true
  default     = "changeme"
}
