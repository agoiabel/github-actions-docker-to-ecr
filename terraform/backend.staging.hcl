bucket  = "your-terraform-state-bucket"       # ← replace
key     = "ecr-demo/staging/terraform.tfstate"
region  = "us-east-1"
encrypt = true
# use_lockfile intentionally omitted for staging
