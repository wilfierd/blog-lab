output "public_ip" {
  description = "Elastic IP of the monitoring instance (Grafana: http://<public_ip>:3000)"
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  description = "Private IP for Promtail push endpoint (loki_push_ip)"
  value       = aws_instance.this.private_ip
}

output "instance_id" {
  description = "Instance ID (for Ansible/SSM targeting)"
  value       = aws_instance.this.id
}
