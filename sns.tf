# -----------------------------------------------------------------------------
# SNS Topic for CloudWatch Alerts
# Add n8n webhook subscription manually after deployment
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "workshop_alerts" {
  name = "${var.project_name}-disk-alerts"

  tags = {
    Name    = "${var.project_name}-disk-alerts"
    Project = var.project_name
  }
}

# SNS Topic Policy to allow CloudWatch to publish
resource "aws_sns_topic_policy" "workshop_alerts" {
  arn = aws_sns_topic.workshop_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "CloudWatchAlarmPolicy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.workshop_alerts.arn
      }
    ]
  })
}
