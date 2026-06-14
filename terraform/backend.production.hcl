bucket       = "your-terraform-state-bucket"          # ← replace
key          = "ecr-demo/production/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true  # native S3 locking (Terraform ≥ 1.10, no DynamoDB needed)
