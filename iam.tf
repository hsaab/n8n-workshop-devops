# -----------------------------------------------------------------------------
# Lambda IAM Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = var.project_name
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # EC2 permissions
  statement {
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:CreateTags",
      "ec2:DescribeTags",
      "ec2:RebootInstances"
    ]
    resources = ["*"]
  }

  # CloudWatch Alarms
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms"
    ]
    resources = ["*"]
  }

  # SSM for sending commands
  statement {
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations"
    ]
    resources = ["*"]
  }

  # IAM PassRole for EC2 instance profile
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2.arn]
  }

  # SNS publish for testing
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.workshop_alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# -----------------------------------------------------------------------------
# EC2 IAM Role (for SSM and CloudWatch Agent)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project = var.project_name
  }
}

# SSM managed policy for Systems Manager
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent policy
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Lambda Invoke Policy (for n8n workflow to invoke Lambda functions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_invoke" {
  statement {
    sid       = "ListLambdaFunctions"
    effect    = "Allow"
    actions   = ["lambda:ListFunctions"]
    resources = ["*"]
  }

  statement {
    sid     = "InvokeWorkshopLambdas"
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.provision.arn,
      "${aws_lambda_function.provision.arn}:*",
      aws_lambda_function.teardown.arn,
      "${aws_lambda_function.teardown.arn}:*",
      aws_lambda_function.fill_disk.arn,
      "${aws_lambda_function.fill_disk.arn}:*",
      aws_lambda_function.reset_disk.arn,
      "${aws_lambda_function.reset_disk.arn}:*",
      aws_lambda_function.spike_cpu.arn,
      "${aws_lambda_function.spike_cpu.arn}:*",
      aws_lambda_function.kill_and_restart.arn,
      "${aws_lambda_function.kill_and_restart.arn}:*",
      aws_lambda_function.corrupt_disk.arn,
      "${aws_lambda_function.corrupt_disk.arn}:*",
      aws_lambda_function.fix_corrupt_disk.arn,
      "${aws_lambda_function.fix_corrupt_disk.arn}:*",
    ]
  }
}

resource "aws_iam_policy" "lambda_invoke" {
  name        = "${var.project_name}-lambda-invoke"
  description = "Policy to invoke workshop Lambda functions"
  policy      = data.aws_iam_policy_document.lambda_invoke.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_user_policy_attachment" "n8n_workshop_user_lambda_invoke" {
  user       = "n8n-workshop-user"
  policy_arn = aws_iam_policy.lambda_invoke.arn
}
