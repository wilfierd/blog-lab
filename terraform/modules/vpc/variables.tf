variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_a" {
  description = "Primary availability zone"
  type        = string
}

variable "az_b" {
  description = "Secondary availability zone"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used for S3 gateway endpoint)"
  type        = string
}
