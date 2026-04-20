output "address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.postgres.address
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "username" {
  description = "RDS master username"
  value       = aws_db_instance.postgres.username
}
