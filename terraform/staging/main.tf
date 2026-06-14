terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block — state is stored locally in terraform.tfstate (gitignored)
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      App         = var.app_name
    }
  }
}

module "ecr" {
  source = "../modules/ecr"

  repository_name      = "${var.app_name}-${var.environment}"
  image_tag_mutability = "IMMUTABLE"

  tags = {
    Component = "ecr"
  }
}

module "iam_oidc" {
  source = "../modules/iam_oidc"

  github_org          = var.github_org
  github_repo         = var.github_repo
  ecr_repository_arns = [module.ecr.repository_arn]
  role_name           = "${var.app_name}-github-actions-${var.environment}"

  tags = {
    Component = "iam"
  }
}
