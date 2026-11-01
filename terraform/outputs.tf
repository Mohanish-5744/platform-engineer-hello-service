output "service_url" {
  description = "Public URL of the service."
  value       = "http://${aws_instance.web.public_ip}"
}

output "health_url" {
  description = "Health endpoint."
  value       = "http://${aws_instance.web.public_ip}/health"
}

output "instance_id" {
  description = "EC2 instance ID (used for SSM sessions and reboot tests)."
  value       = aws_instance.web.id
}

output "security_group_id" {
  description = "Security group ID (check its rules during troubleshooting)."
  value       = aws_security_group.web.id
}

output "ssm_session_command" {
  description = "Open an admin shell without SSH."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.web.id}"
}
