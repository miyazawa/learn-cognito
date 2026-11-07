terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region

  # Tag every resource so it is easy to find (and clean up) in the console
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# Used to build globally-unique names (e.g. the Cognito domain)
data "aws_caller_identity" "current" {}

# Used to pick two AZs for the subnets (an ALB requires at least two)
data "aws_availability_zones" "available" {
  state = "available"
}
