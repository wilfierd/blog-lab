resource "aws_security_group" "alb" {
  name        = "blog-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "blog-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "blog-app-sg"
  description = "Allow traffic from ALB to app instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # NOTE: monitoring → app cross-refs are in aws_security_group_rule below
  # to avoid cyclic dependency with monitoring_sg

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "blog-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "blog-db-sg"
  description = "Allow PostgreSQL and Redis from app instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Redis from app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "blog-db-sg" }
}

resource "aws_security_group" "monitoring" {
  name        = "blog-monitoring-sg"
  description = "Monitoring EC2 - Grafana public, Loki/Prometheus VPC-only"
  vpc_id      = var.vpc_id

  # Grafana: public access, Grafana handles its own auth
  ingress {
    description = "Grafana UI from internet"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NOTE: Loki push from app_sg is in aws_security_group_rule below
  # to avoid cyclic dependency with app_sg

  # Monitoring services: Open for debugging (previously VPC-internal only)
  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Loki API"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Alertmanager"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "CloudWatch Exporter"
    from_port   = 9106
    to_port     = 9106
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "blog-monitoring-sg" }
}

# ─── Cross-reference rules (separate to break cyclic dependency) ─────────────
# Both SGs are created first, then these rules are added after.

resource "aws_security_group_rule" "app_allow_prometheus_scrape" {
  description              = "Prometheus scrape blog metrics from monitoring"
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "app_allow_node_exporter_scrape" {
  description              = "Node Exporter scrape from monitoring"
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "monitoring_allow_loki_push" {
  description              = "Loki push from app EC2 (Promtail)"
  type                     = "ingress"
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.monitoring.id
  source_security_group_id = aws_security_group.app.id
}
