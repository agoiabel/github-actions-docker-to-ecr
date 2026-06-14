output "ecr_repository_url" {
  description = "Push images to this URL"
  value       = module.ecr.repository_url
}

output "github_actions_role_arn" {
  description = "Paste this ARN into your GitHub Actions secret"
  value       = module.iam_oidc.role_arn
}