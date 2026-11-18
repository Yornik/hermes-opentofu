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
  description = "SSH command, or null when ssh_allowed_cidrs is empty."
  value       = length(var.ssh_allowed_cidrs) > 0 ? "ssh ubuntu@${aws_instance.this.public_ip}" : null
}

output "ssm_session_command" {
  description = "Open a shell on the instance via Session Manager (needs the AWS CLI session-manager plugin)."
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}
