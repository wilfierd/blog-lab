output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.this.name
}

output "instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.this.name
}

output "role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.this.arn
}
