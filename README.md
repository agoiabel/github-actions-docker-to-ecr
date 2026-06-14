# GitHub Actions → Docker → ECR

Automated pipeline that builds a Docker image and pushes it to AWS Elastic Container Registry (ECR) using GitHub Actions with keyless authentication (OIDC — no long-lived AWS credentials stored in GitHub).

```
git push → GitHub Actions → docker build → ECR push
                ↑
         OIDC token (no secrets)
```

---

## Table of contents

1. [Project structure](#project-structure)
2. [Docker workflow](#docker-workflow)
3. [Terraform](#terraform)
4. [Environments (staging / production)](#environments)
5. [GitHub repository setup](#github-repository-setup)
6. [Troubleshooting](#troubleshooting)

---

## Project structure

```
.
├── Dockerfile                        # Multi-stage Node.js image
├── server.js                         # Minimal HTTP server
├── package.json
├── .github/workflows/
│   └── build-push.yml                # CI pipeline
└── terraform/
    ├── modules/
    │   ├── ecr/                      # ECR repository + lifecycle policy
    │   └── iam_oidc/                 # OIDC provider + IAM role for GitHub Actions
    ├── staging/
    │   ├── main.tf                   # No backend — local state
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars          # gitignored — your local values
    │   └── terraform.tfvars.example  # committed template
    └── production/
        ├── main.tf                   # backend "s3" {}
        ├── variables.tf
        ├── outputs.tf
        ├── backend.production.hcl    # S3 config — update bucket name before use
        └── terraform.tfvars.example  # committed template
```

---

## Docker workflow

### How the image is built

The `Dockerfile` is a single-stage build on `node:20-alpine`. The app has no npm dependencies (uses only Node's built-in `http` module), so no install step is needed. Files are owned by a non-root user for security.

When you add npm dependencies, restore the two-stage pattern: a `deps` stage that runs `npm ci --omit=dev`, and a `runtime` stage that copies `node_modules` from it.

The `GIT_COMMIT` build arg is injected at CI time and surfaced by the server at `GET /`:

```json
{ "message": "Hello from ECR!", "commit": "abc1234" }
```

### Build and run locally

```bash
# Build
docker build \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  -t ecr-demo:local .

# Run
docker run -p 3000:3000 ecr-demo:local

# Verify
curl http://localhost:3000
```

### GitHub Actions pipeline (`build-push.yml`)

The workflow runs on every push to `main`. Key steps:

1. **Checkout** — fetch source including the commit SHA
2. **Configure AWS credentials** — assume the OIDC role (no secrets stored)
3. **Login to ECR** — short-lived token from `aws ecr get-login-password`
4. **Build & push** — tag with both the short SHA (`sha-<commit>`) and `latest`

The OIDC trust is scoped tightly: only pushes from `refs/heads/main` in `agoiabel/github-actions-docker-to-ecr` can assume the role (enforced by the IAM condition in Terraform).

### Image tags

| Tag | Example | When |
|---|---|---|
| `sha-<commit>` | `sha-abc1234` | Every push — immutable, used for rollbacks |
| `latest` | `latest` | Every push — always points to newest build |

Tags are **immutable** in ECR (enforced by `image_tag_mutability = "IMMUTABLE"`), so re-pushing the same SHA is blocked, preventing silent overwrites.

### ECR lifecycle policy

ECR automatically cleans up old images:

- Untagged images are deleted after **1 day**
- Tagged images with prefix `v`, `main-`, or `sha-` — only the last **30** are kept

---

## Terraform

### Prerequisites

- Terraform >= 1.10.0
- AWS CLI configured (`aws configure` or environment variables)
- An S3 bucket is only required for **production**

### Modules

**`modules/ecr/`** — creates the ECR repository

| Resource | What it does |
|---|---|
| `aws_ecr_repository` | Repository with AES-256 encryption + scan on push |
| `aws_ecr_lifecycle_policy` | Auto-deletes old images (see policy above) |

**`modules/iam_oidc/`** — creates keyless auth for GitHub Actions

| Resource | What it does |
|---|---|
| `aws_iam_openid_connect_provider` | Registers GitHub's OIDC issuer with your AWS account |
| `aws_iam_role` | Role GitHub Actions assumes; trust restricted to `main` branch |
| `aws_iam_policy` | Minimum ECR permissions: `GetAuthorizationToken` + push actions |

### First-time setup

**1. Copy and fill in your variables:**

```bash
# Staging
cp terraform/staging/terraform.tfvars.example terraform/staging/terraform.tfvars
# Edit: set aws_region, github_org, github_repo

# Production (when ready)
cp terraform/production/terraform.tfvars.example terraform/production/terraform.tfvars
# Also update bucket in terraform/production/backend.production.hcl
```

**2. Initialise and apply:**

```bash
# Staging — local state, no S3 bucket needed
cd terraform/staging
terraform init
terraform plan
terraform apply

# Production — S3 state with locking
cd terraform/production
terraform init -backend-config=backend.production.hcl
terraform plan
terraform apply
```

**3. Note the outputs** — you need these to configure GitHub Actions:

```
ecr_repository_url      = 123456789.dkr.ecr.us-east-1.amazonaws.com/ecr-demo-staging
github_actions_role_arn = arn:aws:iam::123456789:role/ecr-demo-github-actions-staging
```

Add `github_actions_role_arn` as a GitHub Actions secret named `AWS_ROLE_ARN` and `ecr_repository_url` as `ECR_REPOSITORY`.

### Outputs reference

| Output | Description |
|---|---|
| `ecr_repository_url` | Full URL to push images to |
| `github_actions_role_arn` | IAM role ARN — paste into your GitHub Actions secret |

### Useful ECR commands

`terraform output ecr_repository_url` returns the full registry URL (used by Docker). AWS CLI commands use only the **short repository name** — everything after the last `/`.

```bash
# Get the full URL
cd terraform/staging && terraform output ecr_repository_url
cd terraform/production && terraform output ecr_repository_url

# List images — use the short name, not the full URL
aws ecr list-images \
  --repository-name ecr-demo-staging \
  --region us-east-1 \
  --output table

aws ecr list-images \
  --repository-name ecr-demo-production \
  --region us-east-1 \
  --output table

# Describe a specific image by tag
aws ecr describe-images \
  --repository-name ecr-demo-staging \
  --image-ids imageTag=latest \
  --region us-east-1

# Delete an image by tag
aws ecr batch-delete-image \
  --repository-name ecr-demo-staging \
  --image-ids imageTag=sha-abc1234 \
  --region us-east-1
```

---

## Environments

The environment is set in `terraform.tfvars`:

```hcl
environment = "staging"    # or "production"
```

**The `environment` value must match the backend config file used at `init` time.** They are intentionally decoupled: the backend file controls S3 state location and locking; the `tfvars` file controls resource names and tags.

| | Staging | Production |
|---|---|---|
| Working directory | `terraform/staging/` | `terraform/production/` |
| Init command | `terraform init` | `terraform init -backend-config=backend.production.hcl` |
| State storage | Local (`terraform.tfstate`) | S3 (`ecr-demo/production/terraform.tfstate`) |
| S3 bucket required | No | Yes |
| State locking | No | Yes — S3 native (`use_lockfile = true`) |
| ECR repo name | `ecr-demo-staging` | `ecr-demo-production` |
| IAM role name | `ecr-demo-github-actions-staging` | `ecr-demo-github-actions-production` |

S3 native locking (Terraform >= 1.10) writes a `.tflock` object in your bucket instead of using DynamoDB — no extra table required.

> **Note:** the local `terraform.tfstate` file produced by staging is gitignored. Never commit it.

---

## GitHub repository setup

These steps must be done manually in the GitHub UI after running `terraform apply`. The workflow will fail until they are in place.

### 1. Actions permissions

Go to **Settings → Actions → General → Workflow permissions** and select:

> **Read and write permissions**

This is required for the workflow to request an OIDC token (`id-token: write`). Without it, GitHub will refuse to issue the token and the AWS credential step will fail.

### 2. Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add the following. Values come from `terraform output` after applying.

| Secret name | Where to get the value |
|---|---|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` |
| `ECR_REPOSITORY` | `terraform output ecr_repository_url` |
| `AWS_REGION` | The region you set in `terraform.tfvars` (e.g. `us-east-1`) |

To print all three at once:

```bash
# From terraform/staging or terraform/production
terraform output github_actions_role_arn
terraform output ecr_repository_url
```

> Secrets are environment-specific. If you run both staging and production, add a separate secret set for each using GitHub's [Environments](https://docs.github.com/en/actions/deployment/targeting-different-deployment-environments) feature, or suffix the secret names (e.g. `AWS_ROLE_ARN_STAGING`, `AWS_ROLE_ARN_PRODUCTION`) and reference them explicitly in the workflow.

### 3. Manually trigger a deployment

The workflow supports manual runs without a code push. In the GitHub UI:

1. Go to the **Actions** tab
2. Select **"Build and Push to ECR"** in the left sidebar
3. Click the **"Run workflow"** dropdown (top-right of the runs list)
4. Choose a branch and click **"Run workflow"**

This is useful for re-deploying the same commit, testing the pipeline, or deploying after a secrets/infrastructure change.

### 4. Verify the setup

Once secrets are added, push a commit to `main` or trigger the workflow manually. In the **Actions** tab you should see the workflow run and succeed. The pushed image will appear in the ECR console under the repository name printed by `terraform output ecr_repository_url`.

---

## Troubleshooting

### Docker

**Image fails to build — `npm install` errors**

```bash
# Inspect the deps stage directly
docker build --target deps -t ecr-demo:deps .
docker run --rm ecr-demo:deps ls node_modules
```

**Container exits immediately**

```bash
# Run with an interactive shell to inspect
docker run --rm -it --entrypoint sh ecr-demo:local
```

**Port already in use**

```bash
# Pick a different host port
docker run -p 3001:3000 ecr-demo:local
```

**Permission denied errors at runtime**

The container runs as a non-root user (`appuser`). If you mount volumes, ensure the host path is readable by UID/GID created inside the container.

---

### GitHub Actions / ECR push

**`Error: Could not assume role`**

The OIDC trust condition only allows pushes from `refs/heads/main`. Check:
- The workflow is triggered from the `main` branch
- `github_org` and `github_repo` in `terraform.tfvars` exactly match your GitHub repo (case-sensitive)
- The IAM role ARN in the GitHub secret matches the Terraform output

Re-apply Terraform after fixing `terraform.tfvars` and grab the new role ARN from the output.

**`Error: tag already exists / tag is immutable`**

ECR is configured with `IMMUTABLE` tags. You cannot push the same commit SHA twice. Force a new build by making a new commit.

**`Error: no basic auth credentials`**

The ECR login step expired or was skipped. The `aws ecr get-login-password` token is valid for 12 hours. Re-run the workflow; it logs in at the start of every run.

**`AccessDeniedException: Not authorized to perform ecr:GetAuthorizationToken`**

The IAM policy only attaches ECR push permissions. Check:
1. The role ARN in the secret is the one Terraform created
2. Run `terraform output github_actions_role_arn` to confirm the current value

---

### Terraform

**`Error: Backend configuration changed`**

Each environment is its own directory with its own `.terraform` cache — they should never conflict. If you see this, you may be running `terraform` from the wrong directory. Confirm with `pwd` and re-init:

```bash
# Staging
cd terraform/staging && terraform init

# Production
cd terraform/production && terraform init -backend-config=backend.production.hcl
```

**`Error: state lock`** (production only)

Another `apply` is running or a previous one crashed without releasing the lock. Check the `.tflock` object in S3:

```bash
aws s3 ls s3://your-bucket/ecr-demo/production/
# Look for terraform.tfstate.tflock
```

Force-unlock only if you are certain no other process is running:

```bash
terraform force-unlock <LOCK_ID>
```

**`ValidationError: environment must be 'staging' or 'production'`**

The `environment` variable only accepts those two values. Update `terraform.tfvars`:

```hcl
environment = "staging"   # or "production"
```

**`Error: creating OIDC provider — EntityAlreadyExists`**

An OIDC provider for `token.actions.githubusercontent.com` already exists in your AWS account. Only one is allowed per account. Import it:

```bash
terraform import \
  module.iam_oidc.aws_iam_openid_connect_provider.github \
  arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

**Enable detailed Terraform logging**

```bash
export TF_LOG=DEBUG        # or INFO, WARN, ERROR
export TF_LOG_PATH=tf.log
terraform apply
```

**Drift — AWS console changes not reflected in state**

```bash
terraform plan -refresh-only    # show what drifted
terraform apply -refresh-only   # pull drift into state without changing infra
```

**Destroy a single environment**

```bash
# Staging
cd terraform/staging && terraform destroy

# Production
cd terraform/production
terraform init -backend-config=backend.production.hcl
terraform destroy
```
