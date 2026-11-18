output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IPv4 address (changes on stop/start)."
  value       = aws_instance.this.public_ip
}

output "ami_id" {
  description = "Ubuntu AMI the instance was launched from."
  value       = aws_instance.this.ami
}

output "ssh_command" {
  description = "SSH command, or null when SSH is not enabled."
  value       = local.ssh_enabled ? "ssh ubuntu@${aws_instance.this.public_ip}" : null
}
