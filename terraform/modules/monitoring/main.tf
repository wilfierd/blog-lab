terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_ami" "al2023_x86" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "this" {
  name = "blog-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 describe — required by Prometheus ec2_sd_configs (tag-based discovery)
resource "aws_iam_policy" "ec2_describe" {
  name = "blog-monitoring-ec2-describe"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_describe" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.ec2_describe.arn
}

# CloudWatch read — required by cloudwatch-exporter
resource "aws_iam_policy" "cloudwatch_read" {
  name = "blog-monitoring-cloudwatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "tag:GetResources",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_read" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.cloudwatch_read.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "blog-monitoring-profile"
  role = aws_iam_role.this.name
}

# ─── EC2 ─────────────────────────────────────────────────────────────────────

resource "aws_eip" "this" {
  domain = "vpc"
  tags   = { Name = "blog-monitoring-eip" }
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023_x86.id
  instance_type          = "t3.small"
  subnet_id              = var.public_subnet_id
  iam_instance_profile   = aws_iam_instance_profile.this.name
  vpc_security_group_ids = [var.monitoring_sg_id]

  # hop_limit=2 allows Docker containers to reach IMDSv2 for IAM credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    mkdir -p /opt/monitoring
    EOF
  )

  tags = { Name = "blog-monitoring" }
}
