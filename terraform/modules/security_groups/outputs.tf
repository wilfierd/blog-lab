output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "App server security group ID"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Database security group ID (RDS + Redis)"
  value       = aws_security_group.db.id
}

output "monitoring_sg_id" {
  description = "Monitoring EC2 security group ID"
  value       = aws_security_group.monitoring.id
}
