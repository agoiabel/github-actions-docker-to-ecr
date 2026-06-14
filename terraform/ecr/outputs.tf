output "repository_url" {
  description = "Full ECR repository URL"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "AWS account ID of the registry"
  value       = aws_ecr_repository.this.registry_id
}