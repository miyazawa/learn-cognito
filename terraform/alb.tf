# Internal ALB: has no public IP and is reachable only from inside the VPC.
# API Gateway reaches it through the VPC Link.
resource "aws_lb" "internal" {
  name               = "${var.project_name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # at least two AZs are required
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip" # Fargate (awsvpc mode) registers task IPs, not instances
  vpc_id      = aws_vpc.main.id

  # Shorter drain time so deployments and `terraform destroy` finish faster
  deregistration_delay = 30

  # The ALB calls the app directly (not through API Gateway), so /health needs no JWT
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Plain HTTP is acceptable here: the traffic never leaves the VPC
# (API Gateway -> VPC Link -> ALB). TLS terminates at API Gateway.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
