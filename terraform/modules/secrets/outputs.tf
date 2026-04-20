output "arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.this.name
}
