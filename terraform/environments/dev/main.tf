module "vpc" {
  source     = "../../modules/vpc"
  vpc_cidr   = var.vpc_cidr
  az_a       = var.az_a
  az_b       = var.az_b
  aws_region = var.aws_region
}

module "security_groups" {
  source   = "../../modules/security_groups"
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr
}

module "s3" {
  source = "../../modules/s3"
}

module "rds" {
  source        = "../../modules/rds"
  db_username   = var.db_username
  db_password   = var.db_password
  db_subnet_ids = module.vpc.private_db_subnet_ids
  db_sg_id      = module.security_groups.db_sg_id
}

module "redis" {
  source     = "../../modules/redis"
  subnet_ids = module.vpc.private_app_subnet_ids
  db_sg_id   = module.security_groups.db_sg_id
}

resource "random_password" "session_secret" {
  length  = 32
  special = true
}

module "secrets" {
  source = "../../modules/secrets"
  secret_string = jsonencode({
    DB_HOST              = module.rds.address
    DB_PORT              = tostring(module.rds.port)
    DB_USER              = module.rds.username
    DB_PASSWORD          = var.db_password
    DB_NAME              = "postgres"
    REDIS_ADDR           = "${module.redis.address}:${module.redis.port}"
    SESSION_SECRET       = random_password.session_secret.result
    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URL  = var.google_redirect_url
    AWS_SECRET_NAME      = "blog/prod/secrets-tf"
    AWS_REGION           = var.aws_region
    AWS_BUCKET_NAME      = module.s3.bucket_name
  })
}

module "alb" {
  source            = "../../modules/alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
}

module "ec2" {
  source             = "../../modules/ec2"
  private_subnet_ids = module.vpc.private_app_subnet_ids
  app_sg_id          = module.security_groups.app_sg_id
  target_group_arn   = module.alb.target_group_arn
  s3_bucket_name     = module.s3.bucket_name
  s3_bucket_arn      = module.s3.bucket_arn
  secret_arn         = module.secrets.arn
  aws_region         = var.aws_region
}

module "monitoring" {
  source           = "../../modules/monitoring"
  public_subnet_id = module.vpc.public_subnet_ids[0]
  monitoring_sg_id = module.security_groups.monitoring_sg_id
  aws_region       = var.aws_region
}
