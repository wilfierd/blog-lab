resource "aws_db_subnet_group" "this" {
  name       = "blog-db-subnet-group"
  subnet_ids = var.db_subnet_ids
  tags       = { Name = "blog-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  identifier             = "blog-postgres"
  engine                 = "postgres"
  engine_version         = "15.15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = { Name = "blog-postgres" }
}
