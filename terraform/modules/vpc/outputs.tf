output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)"
  value       = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs (EC2 ASG)"
  value       = [aws_subnet.private_app_1a.id, aws_subnet.private_app_1b.id]
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs (RDS)"
  value       = [aws_subnet.private_db_1a.id, aws_subnet.private_db_1b.id]
}
