resource "aws_elasticache_subnet_group" "this" {
  name       = "blog-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "blog-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name        = aws_elasticache_subnet_group.this.name
  security_group_ids       = [var.db_sg_id]
  snapshot_retention_limit = 3
  snapshot_window          = "01:00-02:00"

  tags = { Name = "blog-redis" }
}
