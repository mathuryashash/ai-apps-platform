# RDS Postgres 17 with pgvector extension
# Nodes and RDS in private subnets — not publicly accessible (why: no need to expose DB to internet)
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Environment = var.environment }
}

resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Allow Postgres from EKS nodes only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "Postgres from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment }
}

resource "aws_security_group" "eks_nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "EKS node security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment }
}

resource "aws_db_parameter_group" "pgvector" {
  name        = "${var.cluster_name}-pg17-pgvector"
  family      = "postgres17"
  description = "Postgres 17 with pgvector shared_preload_libraries"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = { Environment = var.environment }
}

resource "aws_db_instance" "main" {
  identifier        = "${var.cluster_name}-postgres"
  engine            = "postgres"
  engine_version    = "17"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true # Encryption at rest (required for compliance)

  db_name  = "resume_tracker"
  username = "postgres"
  # Password stored in Secrets Manager — no plaintext in Terraform state
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.pgvector.name

  publicly_accessible = false # Never expose DB to internet
  multi_az            = false # Single-AZ for cost (flip to true in prod)
  skip_final_snapshot = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"

  tags = { Environment = var.environment }
}

# Secrets Manager secrets (no values stored — apps read from here via IRSA)
resource "aws_secretsmanager_secret" "groq_api_key" {
  name        = "${var.cluster_name}/groq-api-key"
  description = "Groq API key for both apps"
  tags        = { Environment = var.environment }
}

resource "aws_secretsmanager_secret" "fernet_key" {
  name        = "${var.cluster_name}/fernet-key"
  description = "Fernet key for jobtracker credential encryption"
  tags        = { Environment = var.environment }
}
