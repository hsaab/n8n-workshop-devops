# -----------------------------------------------------------------------------
# Lambda Function Zip Archives
# -----------------------------------------------------------------------------

data "archive_file" "provision" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/provision"
  output_path = "${path.module}/lambda_functions/provision.zip"
}

data "archive_file" "teardown" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/teardown"
  output_path = "${path.module}/lambda_functions/teardown.zip"
}

data "archive_file" "fill_disk" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/fill_disk"
  output_path = "${path.module}/lambda_functions/fill_disk.zip"
}

data "archive_file" "reset_disk" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/reset_disk"
  output_path = "${path.module}/lambda_functions/reset_disk.zip"
}

data "archive_file" "spike_cpu" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/spike_cpu"
  output_path = "${path.module}/lambda_functions/spike_cpu.zip"
}

data "archive_file" "kill_and_restart" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/kill_and_restart"
  output_path = "${path.module}/lambda_functions/kill_and_restart.zip"
}

data "archive_file" "corrupt_disk" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/corrupt_disk"
  output_path = "${path.module}/lambda_functions/corrupt_disk.zip"
}

data "archive_file" "fix_corrupt_disk" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions/fix_corrupt_disk"
  output_path = "${path.module}/lambda_functions/fix_corrupt_disk.zip"
}

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------

# Provision Lambda - Creates EC2 instance and CloudWatch alarm
resource "aws_lambda_function" "provision" {
  function_name    = "${var.project_name}-provision"
  description      = "Provisions EC2 instance and CloudWatch alarm for workshop user"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 256
  filename         = data.archive_file.provision.output_path
  source_code_hash = data.archive_file.provision.output_base64sha256

  environment {
    variables = {
      AMI_ID               = var.ami_id
      SUBNET_ID            = var.subnet_id
      SECURITY_GROUP_ID    = aws_security_group.workshop.id
      INSTANCE_PROFILE_ARN = aws_iam_instance_profile.ec2.arn
      SNS_TOPIC_ARN        = aws_sns_topic.workshop_alerts.arn
      DISK_THRESHOLD       = var.disk_threshold_percent
      ALARM_PERIOD         = var.alarm_period_seconds
    }
  }

  tags = {
    Name    = "${var.project_name}-provision"
    Project = var.project_name
  }
}

# Teardown Lambda - Terminates EC2 and deletes alarms
resource "aws_lambda_function" "teardown" {
  function_name    = "${var.project_name}-teardown"
  description      = "Terminates EC2 instance and deletes CloudWatch alarm for workshop user"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.teardown.output_path
  source_code_hash = data.archive_file.teardown.output_base64sha256

  tags = {
    Name    = "${var.project_name}-teardown"
    Project = var.project_name
  }
}

# Fill Disk Lambda - Uses SSM to fill disk with large file
resource "aws_lambda_function" "fill_disk" {
  function_name    = "${var.project_name}-fill-disk"
  description      = "Fills disk on workshop EC2 instance using SSM"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.fill_disk.output_path
  source_code_hash = data.archive_file.fill_disk.output_base64sha256

  tags = {
    Name    = "${var.project_name}-fill-disk"
    Project = var.project_name
  }
}

# Reset Disk Lambda - Uses SSM to delete filler files
resource "aws_lambda_function" "reset_disk" {
  function_name    = "${var.project_name}-reset-disk"
  description      = "Resets disk on workshop EC2 instance by removing filler files"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.reset_disk.output_path
  source_code_hash = data.archive_file.reset_disk.output_base64sha256

  tags = {
    Name    = "${var.project_name}-reset-disk"
    Project = var.project_name
  }
}

# Spike CPU Lambda - Uses SSM to trigger CPU stress using stress-ng
resource "aws_lambda_function" "spike_cpu" {
  function_name    = "${var.project_name}-spike-cpu"
  description      = "Triggers CPU spike on workshop EC2 instance using stress-ng"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.spike_cpu.output_path
  source_code_hash = data.archive_file.spike_cpu.output_base64sha256

  tags = {
    Name    = "${var.project_name}-spike-cpu"
    Project = var.project_name
  }
}

# Kill and Restart Lambda - Kills runaway processes and reboots instance
resource "aws_lambda_function" "kill_and_restart" {
  function_name    = "${var.project_name}-kill-and-restart"
  description      = "Kills runaway processes and restarts workshop EC2 instance"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.kill_and_restart.output_path
  source_code_hash = data.archive_file.kill_and_restart.output_base64sha256

  tags = {
    Name    = "${var.project_name}-kill-and-restart"
    Project = var.project_name
  }
}

# Corrupt Disk Lambda - Creates immutable filler file that reset_disk cannot delete
resource "aws_lambda_function" "corrupt_disk" {
  function_name    = "${var.project_name}-corrupt-disk"
  description      = "Creates immutable filler file to simulate escalation scenario"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.corrupt_disk.output_path
  source_code_hash = data.archive_file.corrupt_disk.output_base64sha256

  tags = {
    Name    = "${var.project_name}-corrupt-disk"
    Project = var.project_name
  }
}

# Fix Corrupt Disk Lambda - Admin function to remove immutable flag and delete files
resource "aws_lambda_function" "fix_corrupt_disk" {
  function_name    = "${var.project_name}-fix-corrupt-disk"
  description      = "Removes immutable flag and deletes filler files (admin escalation)"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.fix_corrupt_disk.output_path
  source_code_hash = data.archive_file.fix_corrupt_disk.output_base64sha256

  tags = {
    Name    = "${var.project_name}-fix-corrupt-disk"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda Functions
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "provision" {
  name              = "/aws/lambda/${aws_lambda_function.provision.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "teardown" {
  name              = "/aws/lambda/${aws_lambda_function.teardown.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "fill_disk" {
  name              = "/aws/lambda/${aws_lambda_function.fill_disk.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "reset_disk" {
  name              = "/aws/lambda/${aws_lambda_function.reset_disk.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "spike_cpu" {
  name              = "/aws/lambda/${aws_lambda_function.spike_cpu.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "kill_and_restart" {
  name              = "/aws/lambda/${aws_lambda_function.kill_and_restart.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "corrupt_disk" {
  name              = "/aws/lambda/${aws_lambda_function.corrupt_disk.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "fix_corrupt_disk" {
  name              = "/aws/lambda/${aws_lambda_function.fix_corrupt_disk.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}
