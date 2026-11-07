# Traffic is locked down in three hops, each allowing only the previous one:
#   API Gateway VPC Link --(80)--> internal ALB --(app_port)--> Fargate tasks
#
# Rules are separate aws_vpc_security_group_*_rule resources (not inline blocks)
# because the groups reference each other, which would otherwise create a cycle.

# ---- Security group for the API Gateway VPC Link (the ENIs API Gateway places in the VPC) ----
resource "aws_security_group" "vpclink" {
  name        = "${var.project_name}-vpclink"
  description = "API Gateway VPC Link"
  vpc_id      = aws_vpc.main.id
}

# The VPC Link may only talk to the ALB
resource "aws_vpc_security_group_egress_rule" "vpclink_to_alb" {
  security_group_id            = aws_security_group.vpclink.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# ---- Security group for the internal ALB ----
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Internal ALB"
  vpc_id      = aws_vpc.main.id
}

# Only the VPC Link can reach the ALB listener
resource "aws_vpc_security_group_ingress_rule" "alb_from_vpclink" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.vpclink.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# The ALB may only forward to the application port on Fargate
resource "aws_vpc_security_group_egress_rule" "alb_to_fargate" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.fargate.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# ---- Security group for the Fargate tasks ----
resource "aws_security_group" "fargate" {
  name        = "${var.project_name}-fargate"
  description = "ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id
}

# Only the ALB can reach the app. Even with a public IP, nobody else can connect.
resource "aws_vpc_security_group_ingress_rule" "fargate_from_alb" {
  security_group_id            = aws_security_group.fargate.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# Outbound is needed to pull images from ECR and to send logs to CloudWatch
# (over the internet in public mode, via VPC endpoints in private mode).
resource "aws_vpc_security_group_egress_rule" "fargate_all" {
  security_group_id = aws_security_group.fargate.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---- Security group for the VPC interface endpoints (private_mode only) ----
resource "aws_security_group" "endpoint" {
  name        = "${var.project_name}-endpoint"
  description = "VPC interface endpoints"
  vpc_id      = aws_vpc.main.id
}

# Endpoints are accessed over HTTPS from the Fargate tasks
resource "aws_vpc_security_group_ingress_rule" "endpoint_from_fargate" {
  security_group_id            = aws_security_group.endpoint.id
  referenced_security_group_id = aws_security_group.fargate.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
