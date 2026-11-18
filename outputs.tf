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
  description = "Tailnet-only URL of the Hermes web dashboard (login: the dashboard_username and dashboard_password outputs). Null unless tailnet_domain is set; otherwise the URL is https://<name>.<your-tailnet>.ts.net, and `sudo hermes-dashboard-setup` prints it."
  value       = var.enable_tailnet_dashboard && local.tailnet_fqdn != "" ? "https://${local.tailnet_fqdn}" : null
}

output "dashboard_username" {
  description = "Login for the Hermes dashboard: the username you set, or two generated words. Null when the dashboard is disabled."
  value       = var.enable_tailnet_dashboard ? local.dashboard_username : null
}

output "dashboard_password" {
  description = "Password for the Hermes dashboard (the one you set, or a generated passphrase). Print it with `tofu output -raw dashboard_password`. It is the login seeded at first boot; if you change it on the instance later, this output goes stale. Null when the dashboard is disabled."
  value       = var.enable_tailnet_dashboard ? local.dashboard_password : null
  sensitive   = true
}
