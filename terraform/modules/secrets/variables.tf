variable "secret_string" {
  description = "JSON-encoded secret payload to store in Secrets Manager"
  type        = string
  sensitive   = true
}
