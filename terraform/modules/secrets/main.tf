resource "aws_secretsmanager_secret" "this" {
  name                    = "blog/prod/secrets-tf"
  description             = "Secrets for the blog application"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string
}
