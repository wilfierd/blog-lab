variable "private_subnet_ids" {
  description = "Private subnet IDs for the ASG"
  type        = list(string)
}

variable "app_sg_id" {
  description = "Security group ID for EC2 instances"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN for the ASG"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name (used in user_data to pull app artifacts)"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for IAM policy"
  type        = string
}

variable "secret_arn" {
  description = "Secrets Manager secret ARN for IAM policy"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in user_data)"
  type        = string
}

variable "tailscale_authkey" {
  description = "Tailscale auth key for EC2 instances to auto-join tailnet"
  type        = string
  sensitive   = true
  default     = ""
}
