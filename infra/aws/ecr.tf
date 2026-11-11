# ECR repositories for both apps
resource "aws_ecr_repository" "jobtracker" {
  name                 = "${var.cluster_name}/jobtracker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Environment = var.environment }
}

resource "aws_ecr_repository" "voice_agent" {
  name                 = "${var.cluster_name}/voice-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Environment = var.environment }
}

# Lifecycle policy: keep last 10 images to control storage costs
resource "aws_ecr_lifecycle_policy" "jobtracker" {
  repository = aws_ecr_repository.jobtracker.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "voice_agent" {
  repository = aws_ecr_repository.voice_agent.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
