variable "public_subnet_id" {
  description = "Public subnet ID for the monitoring instance"
  type        = string
}

variable "monitoring_sg_id" {
  description = "Security group ID for the monitoring instance"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
