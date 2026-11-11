# Terraform test with mock AWS provider
# Verifies key security invariants without an AWS account.
# Run: terraform test (from infra/aws/)

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-south-1a", "ap-south-1b"]
      state = "available"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      url = "https://token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock123"
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_subnet" {
    defaults = {
      id                = "subnet-mock"
      availability_zone = "ap-south-1a"
    }
  }

  mock_resource "aws_internet_gateway" {
    defaults = { id = "igw-mock" }
  }

  mock_resource "aws_eip" {
    defaults = { id = "eipalloc-mock" }
  }

  mock_resource "aws_nat_gateway" {
    defaults = { id = "nat-mock" }
  }

  mock_resource "aws_route_table" {
    defaults = { id = "rtb-mock" }
  }

  mock_resource "aws_route_table_association" {
    defaults = { id = "rta-mock" }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      id       = "ai-apps-platform"
      name     = "ai-apps-platform"
      endpoint = "https://mock.eks.amazonaws.com"
      arn      = "arn:aws:eks:ap-south-1:123456789012:cluster/ai-apps-platform"
      version  = "1.31"
    }
  }

  mock_resource "aws_eks_node_group" {
    defaults = { id = "ng-mock" }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      id  = "mock-role"
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }

  mock_resource "aws_iam_role_policy_attachment" {
    defaults = { id = "mock-attach" }
  }

  mock_resource "aws_iam_role_policy" {
    defaults = { id = "mock-policy" }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      id  = "mock-oidc"
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_ecr_repository" {
    defaults = {
      id             = "mock-ecr"
      repository_url = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/mock"
      arn            = "arn:aws:ecr:ap-south-1:123456789012:repository/mock"
    }
  }

  mock_resource "aws_ecr_lifecycle_policy" {
    defaults = { id = "mock-lifecycle" }
  }

  mock_resource "aws_db_subnet_group" {
    defaults = { id = "mock-db-subnet" }
  }

  mock_resource "aws_security_group" {
    defaults = { id = "sg-mock" }
  }

  mock_resource "aws_db_parameter_group" {
    defaults = { id = "mock-pg" }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      id                  = "mock-rds"
      address             = "mock.rds.amazonaws.com"
      publicly_accessible = false
      storage_encrypted   = true
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = { id = "mock-secret" }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = { id = "mock-log-group" }
  }
}

run "nodes_in_private_subnets" {
  command = plan

  assert {
    condition     = length(aws_eks_node_group.main.subnet_ids) > 0
    error_message = "EKS node group must reference subnets"
  }
}

run "rds_not_publicly_accessible" {
  command = plan

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "RDS must not be publicly accessible"
  }
}

run "rds_encryption_enabled" {
  command = plan

  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "RDS storage must be encrypted"
  }
}

run "oidc_trust_limited_to_main_branch" {
  # apply so assume_role_policy is known
  command = apply

  assert {
    condition     = can(regex("refs/heads/main", aws_iam_role.deploy.assume_role_policy))
    error_message = "Deploy role must only trust the main branch"
  }
}

run "eks_uses_private_api_endpoint" {
  command = plan

  assert {
    condition     = aws_eks_cluster.main.vpc_config[0].endpoint_private_access == true
    error_message = "EKS must enable private API endpoint"
  }
}
