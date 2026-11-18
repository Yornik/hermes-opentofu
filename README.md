# hermes-opentofu

OpenTofu config for deploying [Hermes Agent](https://github.com/NousResearch/hermes-agent) on a single EC2 instance.

## What it creates

- 1 EC2 instance: Ubuntu 26.04 LTS (latest Canonical AMI), `m7i-flex.large`, 30 GiB encrypted gp3 root volume, IMDSv2 only
- IAM role + instance profile with `AmazonSSMManagedInstanceCore` (shell access via SSM Session Manager)
- Security group with **no inbound rules** by default and all outbound allowed; port 22 is opened only to the CIDRs you list in `ssh_allowed_cidrs`
- First-boot bootstrap (`user_data`) that installs `git`, `curl`, `tar`, `ca-certificates` and `libatomic1` (the Hermes installer needs them; minimal Ubuntu images lack `libatomic1`)
- Deployed into the default VPC of the target region (`eu-central-1` by default)

State is local (`terraform.tfstate`, git-ignored). Add a remote backend before using this beyond a sandbox.

## Usage

```sh
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

Log in with the sandbox account's credentials first (or pass `-var aws_profile=<profile>`). Common variables are in `variables.tf`:

| Variable | Default | Notes |
|---|---|---|
| `region` | `eu-central-1` | |
| `instance_type` | `m7i-flex.large` | 2 vCPU / 8 GiB |
| `root_volume_size_gb` | `30` | can be grown later without replacing the instance |
| `ubuntu_version` | `26.04` | set `24.04` if a dependency does not support 26.04 yet |
| `ssh_allowed_cidrs` | `[]` | empty = no SSH; use SSM. Use your own IP as a `/32`, avoid `0.0.0.0/0` |
| `ssh_public_key` | `null` | public key to register as an EC2 key pair (login user: `ubuntu`) |
| `ssh_key_name` | `null` | alternative: name of an existing key pair |
| `user_data` | `null` | extra shell snippet appended after the built-in bootstrap |

Put your values in `terraform.tfvars` (git-ignored); see `terraform.tfvars.example`. Setting `ssh_allowed_cidrs` without a key fails the plan.

## Connect

SSM Session Manager (works with no inbound ports; needs the AWS CLI Session Manager plugin):

```sh
aws ssm start-session --target <instance_id> --region <region>
```

SSH (only when `ssh_allowed_cidrs` and a key are set):

```sh
ssh ubuntu@<public_ip>
```

`tofu output` prints both commands. The public IP changes when the instance is stopped and started; attach an Elastic IP if you need it stable.

## Install Hermes

On the instance, as the `ubuntu` user (not root):

```sh
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
hermes setup
hermes gateway install   # runs the gateway as a systemd service so it survives logout
```

Do not run Hermes in the foreground of an SSM session; it stops when the session ends.
