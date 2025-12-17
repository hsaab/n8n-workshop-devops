# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "SNS topic ARN - add n8n webhook subscription to this"
  value       = aws_sns_topic.workshop_alerts.arn
}

output "lambda_provision_arn" {
  description = "ARN of the provision Lambda function"
  value       = aws_lambda_function.provision.arn
}

output "lambda_provision_name" {
  description = "Name of the provision Lambda function"
  value       = aws_lambda_function.provision.function_name
}

output "lambda_teardown_arn" {
  description = "ARN of the teardown Lambda function"
  value       = aws_lambda_function.teardown.arn
}

output "lambda_teardown_name" {
  description = "Name of the teardown Lambda function"
  value       = aws_lambda_function.teardown.function_name
}

output "lambda_fill_disk_arn" {
  description = "ARN of the fill_disk Lambda function"
  value       = aws_lambda_function.fill_disk.arn
}

output "lambda_fill_disk_name" {
  description = "Name of the fill_disk Lambda function"
  value       = aws_lambda_function.fill_disk.function_name
}

output "lambda_reset_disk_arn" {
  description = "ARN of the reset_disk Lambda function"
  value       = aws_lambda_function.reset_disk.arn
}

output "lambda_reset_disk_name" {
  description = "Name of the reset_disk Lambda function"
  value       = aws_lambda_function.reset_disk.function_name
}

output "lambda_spike_cpu_arn" {
  description = "ARN of the spike_cpu Lambda function"
  value       = aws_lambda_function.spike_cpu.arn
}

output "lambda_spike_cpu_name" {
  description = "Name of the spike_cpu Lambda function"
  value       = aws_lambda_function.spike_cpu.function_name
}

output "lambda_kill_and_restart_arn" {
  description = "ARN of the kill_and_restart Lambda function"
  value       = aws_lambda_function.kill_and_restart.arn
}

output "lambda_kill_and_restart_name" {
  description = "Name of the kill_and_restart Lambda function"
  value       = aws_lambda_function.kill_and_restart.function_name
}

output "lambda_corrupt_disk_arn" {
  description = "ARN of the corrupt_disk Lambda function"
  value       = aws_lambda_function.corrupt_disk.arn
}

output "lambda_corrupt_disk_name" {
  description = "Name of the corrupt_disk Lambda function"
  value       = aws_lambda_function.corrupt_disk.function_name
}

output "lambda_fix_corrupt_disk_arn" {
  description = "ARN of the fix_corrupt_disk Lambda function"
  value       = aws_lambda_function.fix_corrupt_disk.arn
}

output "lambda_fix_corrupt_disk_name" {
  description = "Name of the fix_corrupt_disk Lambda function"
  value       = aws_lambda_function.fix_corrupt_disk.function_name
}

output "security_group_id" {
  description = "Security group ID for workshop EC2 instances"
  value       = aws_security_group.workshop.id
}

output "ec2_instance_profile_arn" {
  description = "EC2 instance profile ARN"
  value       = aws_iam_instance_profile.ec2.arn
}

output "ec2_role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.ec2.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}
