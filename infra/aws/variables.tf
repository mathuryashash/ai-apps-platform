variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "ai-apps-platform"
}

variable "environment" {
  description = "Deployment environment (prod/staging)"
  type        = string
  default     = "prod"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "github_repo" {
  description = "GitHub org/repo for OIDC trust (e.g. mathuryashash/ai-apps-platform)"
  type        = string
  default     = "mathuryashash/ai-apps-platform"
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway (costs ~$33/mo)"
  type        = bool
  default     = true
}
