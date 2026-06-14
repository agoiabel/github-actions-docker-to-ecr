variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs this role may push to"
  type        = list(string)
}

variable "role_name" {
  description = "Name for the IAM role"
  type        = string
  default     = "github-actions-ecr-push"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}