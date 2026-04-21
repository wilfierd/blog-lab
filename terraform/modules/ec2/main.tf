# ─── IAM ────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "blog-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "s3" {
  name = "blog-s3-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.s3_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.s3_bucket_arn
      }
    ]
  })
}

resource "aws_iam_policy" "secrets" {
  name = "blog-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [var.secret_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_role_policy_attachment" "secrets" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.secrets.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "blog-ec2-profile"
  role = aws_iam_role.this.name
}

# ─── AMI ────────────────────────────────────────────────────────────────────

data "aws_ami" "amazon_linux_2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.*-arm64"]
  }
}

# ─── LAUNCH TEMPLATE ────────────────────────────────────────────────────────

locals {
  user_data = <<-EOF
    #!/bin/bash
    # Deploy blog app
    aws s3 cp s3://${var.s3_bucket_name}/blog-app /home/ec2-user/blog-app --region ${var.aws_region}
    aws s3 cp s3://${var.s3_bucket_name}/blog.service /home/ec2-user/blog.service --region ${var.aws_region}
    aws s3 sync s3://${var.s3_bucket_name}/frontend/ /home/ec2-user/frontend/ --region ${var.aws_region}
    chmod +x /home/ec2-user/blog-app
    chown -R ec2-user:ec2-user /home/ec2-user
    cp /home/ec2-user/blog.service /etc/systemd/system/blog.service
    systemctl daemon-reload
    systemctl enable blog.service
    systemctl start blog.service

    # Install Tailscale (for monitoring agent connectivity)
    %{if var.tailscale_authkey != ""}
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    tailscale up --authkey=${var.tailscale_authkey} --accept-routes
    %{endif}
  EOF
}

resource "aws_launch_template" "this" {
  name_prefix   = "blog-app-"
  image_id      = data.aws_ami.amazon_linux_2023_arm64.id
  instance_type = "t4g.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

  vpc_security_group_ids = [var.app_sg_id]
  user_data              = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "blog-app-asg" }
  }
}

# ─── AUTO SCALING GROUP ──────────────────────────────────────────────────────

resource "aws_autoscaling_group" "this" {
  name                      = "blog-app-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "blog-app-asg-instance"
    propagate_at_launch = true
  }
}

# ─── SCALING POLICIES ────────────────────────────────────────────────────────

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "blog-scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.this.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "blog-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when CPU > 70%"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "blog-scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.this.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "blog-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale in when CPU < 20%"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}
