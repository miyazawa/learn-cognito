variable "region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Prefix used in resource names"
  type        = string
  default     = "cognito-learning"
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8000
}

variable "image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Number of ECS tasks. Must be 0 until the image is pushed to ECR (`make up` handles this)"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. Must match the platform used to build the image (see PLATFORM in the Makefile)"
  type        = string
  default     = "X86_64"
}

variable "private_mode" {
  description = "true: run Fargate in private subnets and reach AWS services via VPC endpoints (no internet route). false: public subnets + public IP (cheapest, no NAT/endpoints)"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_prefix" {
  description = "Prefix of the Cognito Hosted UI domain. Reserved words such as 'cognito' are not allowed"
  type        = string
  default     = "learning-auth"
}

variable "callback_urls" {
  description = "Extra OAuth callback URLs (the API Gateway URL is added automatically)"
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "Extra OAuth logout URLs (the API Gateway URL is added automatically)"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}
