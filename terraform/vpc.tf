locals {
  # Use the first two available AZs (the ALB and VPC Link need subnets in 2 AZs)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Where Fargate tasks run: private subnets in private_mode, public subnets otherwise
  fargate_subnet_ids = var.private_mode ? aws_subnet.private[*].id : aws_subnet.public[*].id
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for private DNS names of VPC endpoints and for the internal ALB DNS name
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

# ---------------------------------------------------------------------------
# Public subnets: internal ALB, VPC Link and (by default) Fargate tasks.
# The ALB is "internal", so it gets no public IP even though it sits here.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.0.1.0/24, 10.0.2.0/24

  # Public IPs are assigned explicitly by the ECS service, not by the subnet
  tags = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Default route to the internet (used by Fargate to pull from ECR in public mode)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private subnets (only when private_mode = true)
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = var.private_mode ? 2 : 0

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11) # 10.0.11.0/24, 10.0.12.0/24

  tags = { Name = "${var.project_name}-private-${count.index}" }
}

# Intentionally has no default route: there is no path to the internet.
# AWS services are reached only through the VPC endpoints below.
resource "aws_route_table" "private" {
  count = var.private_mode ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = var.private_mode ? 2 : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# ---------------------------------------------------------------------------
# VPC endpoints (only when private_mode = true)
# ---------------------------------------------------------------------------

# Gateway endpoint (free). ECR stores image layers in S3, so it is required for image pulls.
resource "aws_vpc_endpoint" "s3" {
  count = var.private_mode ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private[0].id]

  tags = { Name = "${var.project_name}-s3" }
}

# Interface endpoints (hourly charge each):
#   ecr.api -> ECR API (auth token, image manifest)
#   ecr.dkr -> Docker registry endpoint (image pull)
#   logs    -> CloudWatch Logs (container log output)
resource "aws_vpc_endpoint" "interface" {
  for_each = var.private_mode ? toset(["ecr.api", "ecr.dkr", "logs"]) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true # the default AWS hostnames resolve to the endpoint

  tags = { Name = "${var.project_name}-${each.key}" }
}
