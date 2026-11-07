# Recipes use ">" instead of a tab, so the file is safe from tab/space mix-ups
.RECIPEPREFIX = >
# Run each recipe in a single shell so variables persist between lines
.ONESHELL:
SHELL := /bin/bash
# Stop at the first failing command (and fail on errors inside pipes)
.SHELLFLAGS := -eu -o pipefail -c

REGION  ?= ap-northeast-1
TF      := terraform -chdir=terraform
IMAGE_TAG ?= latest
# Must match cpu_architecture in variables.tf (use linux/arm64 for ARM64)
PLATFORM  ?= linux/amd64

# Read from Terraform outputs. "=" (not ":=") evaluates them lazily, only when a recipe uses them,
# so targets that run before the first apply do not fail.
ECR_URL   = $(shell $(TF) output -raw ecr_repository_url)
API_URL   = $(shell $(TF) output -raw api_endpoint)
POOL_ID   = $(shell $(TF) output -raw user_pool_id)
CLIENT_ID = $(shell $(TF) output -raw user_pool_client_id)

.PHONY: init apply push up down create-user token test logs

init:
> $(TF) init

apply:
> $(TF) apply

# Build the image and push it to ECR.
# $(firstword $(subst /, ,$(ECR_URL))) extracts the registry host (account.dkr.ecr...) from the repository URL.
push:
> aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(ECR_URL)))
> docker build --platform $(PLATFORM) -t $(ECR_URL):$(IMAGE_TAG) app
> docker push $(ECR_URL):$(IMAGE_TAG)

# One-shot deploy. The ECS service cannot start before the image exists in ECR, so:
#   1) create everything with 0 tasks  2) push the image  3) scale up to 1 task
up:
> $(TF) init
> $(TF) apply -auto-approve -var desired_count=0
> $(MAKE) push
> $(TF) apply -auto-approve -var desired_count=1
> $(TF) output

# Delete everything to stop charges (the ALB and public IPs are billed while they exist)
down:
> $(TF) destroy -auto-approve

# Create a confirmed test user (no verification email needed).
# Usage: make create-user EMAIL=you@example.com PASSWORD='Passw0rd!'
create-user:
> aws cognito-idp admin-create-user --region $(REGION) --user-pool-id $(POOL_ID) \
>   --username "$(EMAIL)" --user-attributes Name=email,Value="$(EMAIL)" Name=email_verified,Value=true \
>   --message-action SUPPRESS
> aws cognito-idp admin-set-user-password --region $(REGION) --user-pool-id $(POOL_ID) \
>   --username "$(EMAIL)" --password '$(PASSWORD)' --permanent

# Get a token with the USER_PASSWORD_AUTH flow (testing only; real apps use the code flow).
# Usage: make token EMAIL=... PASSWORD=...   (add TOKEN_TYPE=IdToken for the ID token)
TOKEN_TYPE ?= AccessToken
token:
> @aws cognito-idp initiate-auth --region $(REGION) --client-id $(CLIENT_ID) \
>   --auth-flow USER_PASSWORD_AUTH --auth-parameters USERNAME="$(EMAIL)",PASSWORD='$(PASSWORD)' \
>   --query 'AuthenticationResult.$(TOKEN_TYPE)' --output text

# Smoke test of the three cases. Usage: make test EMAIL=... PASSWORD=...
# "$$" passes a literal "$" to the shell (make would otherwise expand it).
test:
> API="$(API_URL)"
> echo "--- GET /health (no auth) -> expect 200"
> curl -s -w ' [%{http_code}]\n' "$$API/health"
> echo "--- GET /me (no token) -> expect 401; the request never reaches ECS"
> curl -s -w ' [%{http_code}]\n' "$$API/me"
> TOKEN=$$($(MAKE) --no-print-directory -s token EMAIL="$(EMAIL)" PASSWORD='$(PASSWORD)')
> echo "--- GET /me (with Bearer token) -> expect 200"
> curl -s -w '\n[%{http_code}]\n' -H "Authorization: Bearer $$TOKEN" "$$API/me"

# Follow the application logs in CloudWatch Logs
logs:
> aws logs tail /ecs/cognito-learning --follow --region $(REGION)
