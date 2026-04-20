output "dns_name" {
  description = "ALB public DNS name"
  value       = aws_lb.this.dns_name
}

output "arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "Target group ARN for ASG attachment"
  value       = aws_lb_target_group.this.arn
}
