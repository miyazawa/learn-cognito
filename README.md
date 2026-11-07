# Cognito + API Gateway (HTTP API) + ECS Fargate learning environment

A small environment for learning Amazon Cognito authentication, deployable with Terraform.
It is built for learning and low cost, not for production use.

```
Browser / curl --> API Gateway (HTTP API, Cognito JWT authorizer)
                      --> VPC Link --> internal ALB --> ECS Fargate (FastAPI)

Cognito User Pool <-- sign-in (the client talks to Cognito directly and receives the tokens)
```

- API Gateway validates the JWT, so only authenticated requests reach the app (except the public `/health`, `/` and `/callback` routes).
- The ALB is internal. Fargate runs in public subnets with a public IP so it can pull images without a NAT Gateway, but its security group only accepts traffic from the ALB.

## Prerequisites

- Terraform >= 1.5
- AWS CLI (authenticated, with permission to create the resources above)
- Docker
- make

## Project layout

```
.
├── Makefile
├── app/                 FastAPI app, login page (index.html), Dockerfile
└── terraform/           VPC, security groups, Cognito, ECR, ALB, ECS, API Gateway
```

## Deploy

```
make up
```

This creates the infrastructure with 0 tasks, builds and pushes the image to ECR, then scales the service to 1 task.
The first run takes about 10 minutes. The default region is `ap-northeast-1`.

## Try it

### In the browser (authorization code flow + PKCE)

1. Create a test user:
   ```
   make create-user EMAIL=you@example.com PASSWORD='Passw0rd!'
   ```
2. Open the URL printed by:
   ```
   terraform -chdir=terraform output -raw app_url
   ```
3. Click **Login**, sign in on the Cognito Hosted UI, and you are sent back to `/callback`.
   The page exchanges the code for tokens, then shows the decoded access/ID tokens and the response from `/me`.
   The buttons let you call `/me` with the access token, the ID token, or no token (expect 401).

### From the command line

```
make test EMAIL=you@example.com PASSWORD='Passw0rd!'
```

This checks three cases: `/health` without a token (200), `/me` without a token (401), and `/me` with a Bearer token (200).
`make token EMAIL=... PASSWORD=...` prints just the access token (add `TOKEN_TYPE=IdToken` for the ID token).
This uses the `USER_PASSWORD_AUTH` flow, which is for testing only.

### Logs

```
make logs
```

Follows the application logs in CloudWatch Logs. A request rejected with 401 never reaches ECS, so it does not appear here.

## Clean up

```
make down
```

The internal ALB and the public IP are billed while they exist. Always destroy the environment when you are done.

## Options

| Option | How |
|---|---|
| Private subnets + VPC endpoints (no route to the internet) | `terraform apply -var private_mode=true`. Creates endpoints for ecr.api, ecr.dkr, logs and s3. Interface endpoints are billed hourly. |
| ARM64 (Graviton) | Set `-var cpu_architecture=ARM64` and run `make PLATFORM=linux/arm64`. |
| Extra callback / logout URLs | Set `callback_urls` / `logout_urls` in `terraform.tfvars`. The API Gateway URL is always registered automatically. |
| Cognito domain prefix | Set `domain_prefix` (it cannot contain the reserved word `cognito`). |

## Notes

- Tokens are shown on the page and kept in `sessionStorage` for learning purposes only. Real apps should keep tokens in memory or use a server-side session (BFF).
- The HTTP API JWT authorizer does not check whether a token has been revoked, so a token stays valid until it expires (60 minutes by default).
- Terraform state is stored locally and ignored by `.gitignore`. Do not commit `*.tfstate` or `*.tfvars`; they can contain account-specific values.
