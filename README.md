# n8n DevOps Workshop Infrastructure

Terraform infrastructure for an n8n DevOps workshop where participants provision EC2 instances and trigger disk space alerts via automated workflows.

## Overview

This project creates AWS infrastructure that allows workshop participants to:
- Provision their own EC2 instance with CloudWatch monitoring
- Simulate disk space issues and CPU spikes
- Receive CloudWatch alerts via n8n webhooks
- Use AI agents to decide on remediation actions
- Clean up resources when done

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                      n8n Workflow                                                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐ │
│  │ Provision│ │Fill Disk │ │Reset Disk│ │Spike CPU │ │ Teardown │ │Kill and Restart │ │Corrupt Disk │ │Fix Corrupt Disk │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬────────┘ └──────┬──────┘ └────────┬────────┘ │
└───────┼────────────┼────────────┼────────────┼────────────┼────────────────┼────────────────┼──────────────────┼──────────┘
        │            │            │            │            │                │                │                  │
        ▼            ▼            ▼            ▼            ▼                ▼                ▼                  ▼
┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   AWS Lambda Functions                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────────┐ ┌─────────────┐ ┌─────────────────┐ │
│  │ provision│ │fill_disk │ │reset_disk│ │spike_cpu │ │ teardown │ │kill_and_restart │ │corrupt_disk │ │fix_corrupt_disk │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬────────┘ └──────┬──────┘ └────────┬────────┘ │
└───────┼────────────┼────────────┼────────────┼────────────┼────────────────┼────────────────┼──────────────────┼──────────┘
        │            │            │            │            │                 │
        ▼            │            │            │            ▼                 │
┌───────────────┐    │            │            │    ┌───────────────┐         │
│     EC2       │◄───┴────────────┴────────────┴────│  CloudWatch   │         │
│   Instance    │         SSM Commands              │    Alarms     │◄────────┘
│ (per user)    │                                   │ (Disk + CPU)  │    EC2 Reboot
└───────┬───────┘                                   └───────┬───────┘
        │                                                   │
        │ CloudWatch                                        ▼
        │ Agent Metrics                             ┌───────────────┐
        │ + CPU Metrics                             │  SNS Topic    │
        └───────────────────────────────────────────►───────┬───────┘
                                                            │
                                                            ▼
                                                    ┌───────────────┐
                                                    │ n8n Webhook   │
                                                    │ (Alert Handler│
                                                    │ + AI Agent)   │
                                                    └───────────────┘
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions to create:
  - IAM roles and policies
  - Lambda functions
  - EC2 instances
  - CloudWatch alarms and log groups
  - SNS topics
  - Security groups

## Quick Start

### 1. Get Required AWS Information

```bash
# Get the latest Amazon Linux 2023 AMI ID
aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text

# Get your default VPC ID
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text

# Get subnet ID (replace YOUR_VPC_ID)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=YOUR_VPC_ID" \
  --query 'Subnets[?MapPublicIpOnLaunch==`true`].[SubnetId,AvailabilityZone]' \
  --output table
```

### 2. Configure Terraform Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region             = "us-east-1"
project_name           = "workshop"
ami_id                 = "ami-0abcdef1234567890"  # From step 1
vpc_id                 = "vpc-0123456789abcdef0"  # From step 1
subnet_id              = "subnet-0123456789abcdef0"  # From step 1
instance_type          = "t3.micro"
disk_threshold_percent = 80
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 4. Subscribe n8n Webhook to SNS

After deployment, subscribe your n8n webhook URL to the SNS topic:

```bash
# Get the SNS topic ARN from outputs
SNS_ARN=$(terraform output -raw sns_topic_arn)

# Subscribe your n8n webhook
aws sns subscribe \
  --topic-arn "$SNS_ARN" \
  --protocol https \
  --notification-endpoint "https://your-n8n-instance.com/webhook/your-webhook-id"
```

## Lambda Functions

### provision

Creates an EC2 instance for a workshop participant with disk and CPU monitoring.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "instance_name": "workshop-user123",
  "public_ip": "54.123.45.67",
  "username": "user123",
  "exists": false,
  "alarm_names": ["workshop-user123-disk-high", "workshop-user123-cpu-high"],
  "message": "Instance provisioned successfully"
}
```

**What it does:**
- Checks if user already has an instance (prevents duplicates)
- Creates t3.micro EC2 with 30GB gp3 volume
- Installs CloudWatch Agent for disk metrics and stress-ng for CPU testing
- Creates CloudWatch alarm for disk usage > 80%
- Creates CloudWatch alarm for CPU utilization > 80%
- Tags resources with workshop-user for tracking

---

### fill_disk

Fills the disk on a user's instance to trigger the CloudWatch alarm.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "command_id": "abc123-def456",
  "status": "Success",
  "output": "Filesystem      Size  Used Avail Use% Mounted on\n/dev/xvda1      8.0G  7.2G  0.8G  90% /",
  "message": "Disk filled successfully"
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand to create a 6GB file: `fallocate -l 6G /tmp/filler.dat`
- Waits for command completion
- Returns disk usage status

---

### reset_disk

Removes filler files to reset disk usage. Detects immutable files and returns escalation info when deletion fails.

**Input:**
```json
{
  "username": "user123"
}
```

**Output (success):**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "disk_status": "Filesystem      Size  Used Avail Use% Mounted on\n/dev/xvda1      8.0G  1.2G  6.8G  15% /",
  "message": "Disk reset successfully"
}
```

**Output (escalation needed):**
```json
{
  "success": false,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "error": "Cannot delete immutable file - Operation not permitted",
  "requires_escalation": true,
  "disk_status": "...",
  "suggested_action": "Manual intervention required: run 'sudo chattr -i /var/tmp/filler_corrupt.dat' then delete the file"
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand: `rm -fv /var/tmp/filler*.dat`
- Detects permission errors from immutable files
- Returns escalation info if automated remediation fails
- Returns disk usage status

---

### teardown

Terminates a user's instance and cleans up resources.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "terminated_instances": ["i-0123456789abcdef0"],
  "deleted_alarms": ["workshop-user123-disk-high", "workshop-user123-cpu-high"],
  "username": "user123",
  "message": "Teardown complete. Terminated 1 instance(s)."
}
```

**What it does:**
- Finds instances by workshop-user tag
- Terminates the EC2 instance
- Deletes both disk and CPU CloudWatch alarms

---

### spike_cpu

Triggers a CPU spike on a user's instance using stress-ng.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "message": "CPU stress started - running for 300 seconds"
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand to run: `stress-ng --cpu 2 --timeout 300s &`
- Stress runs for 5 minutes in the background
- Triggers the CPU high alarm (> 80% threshold)

---

### kill_and_restart

Kills runaway processes and reboots the instance (remediation action).

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "actions": ["killed stress-ng", "rebooted instance"],
  "message": "Process killed and instance rebooted"
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand to run: `pkill -9 stress-ng || true`
- Reboots the instance using EC2 API
- Useful as an AI agent remediation action for CPU alerts

---

### corrupt_disk

Creates a filler file with the immutable flag set, so the regular reset_disk Lambda cannot delete it. Used to demonstrate escalation scenarios.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "disk_status": "Filesystem      Size  Used Avail Use% Mounted on\n/dev/xvda1      30G   26G  4.0G  87% /",
  "message": "Disk corrupted with immutable file. Automated reset will fail - requires manual intervention."
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand: `fallocate -l 25G /var/tmp/filler_corrupt.dat && chattr +i /var/tmp/filler_corrupt.dat`
- Creates a 25GB file with the immutable attribute
- When reset_disk tries to delete it, it will fail with "Operation not permitted"
- Demonstrates scenarios where automated remediation fails

---

### fix_corrupt_disk

Admin-only function that removes the immutable flag and deletes all filler files. This is the "human intervention" that fixes what the automated reset_disk couldn't.

**Input:**
```json
{
  "username": "user123"
}
```

**Output:**
```json
{
  "success": true,
  "instance_id": "i-0123456789abcdef0",
  "username": "user123",
  "disk_status": "Filesystem      Size  Used Avail Use% Mounted on\n/dev/xvda1      30G  1.2G   29G   4% /",
  "message": "Corrupt disk fixed. Immutable flag removed and files deleted."
}
```

**What it does:**
- Finds the user's running instance
- Uses SSM SendCommand: `chattr -i /var/tmp/filler_corrupt.dat && rm -f /var/tmp/filler*.dat`
- Removes the immutable flag from the corrupt file
- Deletes all filler files
- Represents the escalation path when AI agent remediation fails

## Testing Lambda Functions

### Via AWS CLI

```bash
# Provision an instance
aws lambda invoke --function-name n8n-workshop-devops-provision \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Fill the disk (wait ~5 min for CloudWatch agent to start)
aws lambda invoke --function-name n8n-workshop-devops-fill-disk \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Reset the disk
aws lambda invoke --function-name n8n-workshop-devops-reset-disk \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Spike the CPU (triggers CPU alarm after ~1-2 minutes)
aws lambda invoke --function-name n8n-workshop-devops-spike-cpu \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Kill stress-ng and reboot instance (remediation)
aws lambda invoke --function-name n8n-workshop-devops-kill-and-restart \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Corrupt the disk with immutable file (escalation demo)
aws lambda invoke --function-name n8n-workshop-devops-corrupt-disk \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Try reset_disk - will fail with requires_escalation=true
aws lambda invoke --function-name n8n-workshop-devops-reset-disk \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Fix corrupt disk (admin escalation)
aws lambda invoke --function-name n8n-workshop-devops-fix-corrupt-disk \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Teardown the instance
aws lambda invoke --function-name n8n-workshop-devops-teardown \
  --payload '{"username": "testuser"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

### Via AWS Console

1. Navigate to Lambda > Functions
2. Select the function (e.g., `workshop-provision`)
3. Click "Test" tab
4. Create test event with JSON payload
5. Click "Test" to execute

## n8n Integration

### SNS Alert Payload

When a CloudWatch alarm triggers, n8n receives a payload like:

```json
{
  "Type": "Notification",
  "MessageId": "abc123",
  "TopicArn": "arn:aws:sns:us-east-1:123456789012:workshop-disk-alerts",
  "Subject": "ALARM: \"workshop-user123-disk-high\" in US East (N. Virginia)",
  "Message": "{\"AlarmName\":\"workshop-user123-disk-high\",\"AlarmDescription\":\"Disk usage alert for workshop user user123\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"Threshold Crossed: 1 datapoint (85.5) was greater than the threshold (80.0).\",\"StateChangeTime\":\"2024-01-15T10:30:00.000+0000\",\"Region\":\"US East (N. Virginia)\",\"OldStateValue\":\"OK\",\"Trigger\":{\"MetricName\":\"disk_used_percent\",\"Namespace\":\"Workshop\",\"Dimensions\":[{\"name\":\"InstanceId\",\"value\":\"i-0123456789abcdef0\"}]}}",
  "Timestamp": "2024-01-15T10:30:05.000Z"
}
```

### Suggested n8n Workflows

**Basic Alert Workflow:**
1. **Webhook Trigger** - Receives SNS notifications
2. **Parse Message** - Extract alarm details from JSON
3. **Switch Node** - Route based on alarm state (ALARM/OK)
4. **Notify** - Send Slack/email/Teams notification
5. **Optional: Auto-remediate** - Call reset_disk Lambda

**AI Agent Remediation Workflow (CPU Alerts):**
1. **Webhook Trigger** - Receives CPU alarm from SNS
2. **Parse Message** - Extract alarm name and instance details
3. **AI Agent Node** - Decides remediation action based on context
4. **Tool Nodes** - Available actions for AI to choose:
   - `kill_and_restart` - Kill stress-ng and reboot instance
   - `reset_disk` - Clear disk space (if disk-related)
   - Notify only - Just send alert without remediation
5. **Notify** - Send result to Slack/Teams

## File Structure

```
n8n-workshop-devops/
├── main.tf                 # Provider configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── iam.tf                  # IAM roles and policies
├── security.tf             # Security group
├── sns.tf                  # SNS topic and policies
├── lambda.tf               # Lambda functions and log groups
├── terraform.tfvars        # Your configuration (git-ignored)
├── terraform.tfvars.example # Example configuration
└── lambda_functions/
    ├── provision/
    │   └── lambda_function.py
    ├── teardown/
    │   └── lambda_function.py
    ├── fill_disk/
    │   └── lambda_function.py
    ├── reset_disk/
    │   └── lambda_function.py
    ├── spike_cpu/
    │   └── lambda_function.py
    ├── kill_and_restart/
    │   └── lambda_function.py
    ├── corrupt_disk/
    │   └── lambda_function.py
    └── fix_corrupt_disk/
        └── lambda_function.py
```

## Outputs

| Output | Description |
|--------|-------------|
| `sns_topic_arn` | SNS topic ARN for webhook subscription |
| `lambda_provision_arn` | Provision Lambda ARN |
| `lambda_provision_name` | Provision Lambda name |
| `lambda_teardown_arn` | Teardown Lambda ARN |
| `lambda_teardown_name` | Teardown Lambda name |
| `lambda_fill_disk_arn` | Fill disk Lambda ARN |
| `lambda_fill_disk_name` | Fill disk Lambda name |
| `lambda_reset_disk_arn` | Reset disk Lambda ARN |
| `lambda_reset_disk_name` | Reset disk Lambda name |
| `lambda_spike_cpu_arn` | Spike CPU Lambda ARN |
| `lambda_spike_cpu_name` | Spike CPU Lambda name |
| `lambda_kill_and_restart_arn` | Kill and restart Lambda ARN |
| `lambda_kill_and_restart_name` | Kill and restart Lambda name |
| `lambda_corrupt_disk_arn` | Corrupt disk Lambda ARN |
| `lambda_corrupt_disk_name` | Corrupt disk Lambda name |
| `lambda_fix_corrupt_disk_arn` | Fix corrupt disk Lambda ARN |
| `lambda_fix_corrupt_disk_name` | Fix corrupt disk Lambda name |
| `security_group_id` | Security group ID |
| `ec2_instance_profile_arn` | EC2 instance profile ARN |
| `ec2_role_arn` | EC2 IAM role ARN |
| `lambda_role_arn` | Lambda IAM role ARN |

## Cleanup

To destroy all infrastructure:

```bash
# First, teardown any running workshop instances
aws lambda invoke --function-name workshop-teardown \
  --payload '{"username": "ALL_USERS"}' \
  --cli-binary-format raw-in-base64-out \
  response.json

# Then destroy Terraform resources
terraform destroy
```

**Note:** The teardown Lambda only terminates instances by specific username. You may need to manually terminate instances or run teardown for each user before destroying the infrastructure.

## Security Considerations

- **No SSH access**: Instances use SSM for management (no inbound ports)
- **Outbound only**: Security group allows only outbound traffic for SSM/CloudWatch
- **Least privilege**: IAM roles have minimal required permissions
- **Resource tagging**: All resources tagged for easy identification and cleanup

## Troubleshooting

### SSM Commands Failing

1. Verify the instance has a public IP (required for SSM)
2. Check the instance IAM role has `AmazonSSMManagedInstanceCore` policy
3. Wait 2-3 minutes after instance launch for SSM agent to register

### CloudWatch Alarm Not Triggering

1. Wait 5 minutes after instance launch for CloudWatch agent to start
2. Verify metrics appear in CloudWatch > Metrics > Workshop namespace
3. Check alarm dimensions match the actual metric dimensions

### Lambda Timeout

- Default timeout is set to handle SSM command waits
- If commands take longer, increase Lambda timeout in `lambda.tf`

## License

MIT
