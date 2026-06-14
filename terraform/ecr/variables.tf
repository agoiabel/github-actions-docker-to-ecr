variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE image tags"
  type        = string
  default     = "IMMUTABLE"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}