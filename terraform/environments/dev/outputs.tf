output "alb_dns_name" {
  description = "ALB DNS — use this URL to access the application"
  value       = module.alb.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.address
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.address
}

output "s3_bucket_name" {
  description = "S3 bucket name for uploads"
  value       = module.s3.bucket_name
}

output "secrets_manager_arn" {
  description = "Secrets Manager ARN"
  value       = module.secrets.arn
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.ec2.asg_name
}
