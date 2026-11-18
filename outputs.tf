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

output "tailscale_up_command" {
  description = "Run this on the instance to join your tailnet by hand. --hostname fixes the node name that the dashboard URL is built from. Null when tailscale_auth_key is set, because the instance joins by itself at first boot."
  value       = local.has_auth_key ? null : "sudo tailscale up --ssh --hostname=${var.name}"
}

output "dashboard_url" {
  description = "Tailnet-only URL of the Hermes web dashboard (login: admin, password in /etc/hermes-dashboard/dashboard.env on the instance). Null unless tailnet_domain is set; otherwise run `sudo hermes-dashboard-setup` after joining and it prints the URL."
  value       = var.enable_tailnet_dashboard && local.tailnet_fqdn != "" ? "https://${local.tailnet_fqdn}" : null
}
