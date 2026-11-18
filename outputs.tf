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

output "ssm_session_command" {
  description = "Open a shell on the instance via Session Manager (needs the AWS CLI session-manager plugin)."
  value       = "aws ssm start-session --target ${aws_instance.this.id} --region ${var.region}"
}
