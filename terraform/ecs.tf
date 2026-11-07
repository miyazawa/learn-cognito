resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7 # keep logs short-lived to avoid storage costs
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------
# Trust policy shared by both roles: only ECS tasks can assume them
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task execution role: used by ECS itself (not by the app) to pull the image
# from ECR and to write container logs to CloudWatch Logs.
resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: the identity the application code runs as when it calls AWS APIs.
# Empty for now because the app does not call any AWS service.
resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ---------------------------------------------------------------------------
# Task definition / service
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc" # each task gets its own ENI (required for Fargate)
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture # must match the architecture the image was built for
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    # Settings the login page needs. They are not secrets (the client has no secret).
    environment = [
      { name = "COGNITO_BASE_URL", value = local.cognito_base_url },
      { name = "COGNITO_CLIENT_ID", value = aws_cognito_user_pool_client.app.id },
    ]

    portMappings = [{
      containerPort = var.app_port
      protocol      = "tcp"
    }]

    # Send stdout/stderr to CloudWatch Logs (view with `make logs`)
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Do not let the ALB health check kill a task while the app is still starting
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets         = local.fargate_subnet_ids
    security_groups = [aws_security_group.fargate.id]

    # A public IP is what lets the task reach ECR without a NAT Gateway (public mode).
    # Inbound access is still blocked by the security group.
    assign_public_ip = !var.private_mode
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  # If a new deployment never becomes healthy, stop and roll back to the previous one
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # The target group must be attached to a listener before the service can register with it
  depends_on = [aws_lb_listener.http]
}
