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
