# -----------------------------------------------------------------------------
# Security Group for Workshop EC2 Instances
# Only allows outbound traffic - SSM doesn't require inbound rules
# -----------------------------------------------------------------------------

resource "aws_security_group" "workshop" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for workshop EC2 instances - outbound only for SSM"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic (required for SSM, CloudWatch, package updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}
