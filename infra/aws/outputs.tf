output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "ecr_jobtracker_url" {
  description = "ECR URL for jobtracker image"
  value       = aws_ecr_repository.jobtracker.repository_url
}

output "ecr_voice_agent_url" {
  description = "ECR URL for voice-agent image"
  value       = aws_ecr_repository.voice_agent.repository_url
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC deploy"
  value       = aws_iam_role.deploy.arn
}
