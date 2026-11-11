terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Remote state: S3 + DynamoDB lock (not created here — documented only)
  # backend "s3" {
  #   bucket         = "ai-apps-platform-tfstate"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "ai-apps-platform-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}
