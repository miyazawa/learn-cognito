# HTTP API: the public entry point. It terminates TLS, validates the Cognito JWT,
# and forwards only authenticated requests to the internal ALB.
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

# Lets API Gateway reach private resources in the VPC (the internal ALB)
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.project_name}-vpclink"
  security_group_ids = [aws_security_group.vpclink.id]
  subnet_ids         = aws_subnet.public[*].id
}

# ---------------------------------------------------------------------------
# Cognito JWT authorizer
# ---------------------------------------------------------------------------
# API Gateway checks the token's signature (using the pool's public keys), expiry,
# issuer and audience. Requests that fail never reach the backend (401).
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"] # expects "Authorization: Bearer <token>"

  jwt_configuration {
    issuer = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"

    # Matches `aud` in ID tokens and `client_id` in access tokens
    audience = [aws_cognito_user_pool_client.app.id]
  }
}

# ---------------------------------------------------------------------------
# Integrations: how API Gateway forwards requests to the ALB
# ---------------------------------------------------------------------------

# For routes that need no authentication: forward the request as-is
resource "aws_apigatewayv2_integration" "public" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.http.arn # for a VPC Link, the target is the ALB listener
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  # VPC Link integrations only support payload format 1.0
  payload_format_version = "1.0"
}

# For routes that require a JWT: also pass verified claims to the app as headers.
# "overwrite" replaces any header the client sent with the same name, so a caller
# cannot spoof X-User-Sub. HTTP APIs do not forward authorizer claims automatically.
resource "aws_apigatewayv2_integration" "protected" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.http.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:header.X-User-Sub" = "$context.authorizer.claims.sub"
  }
}

# ---------------------------------------------------------------------------
# Routes (the most specific route wins; $default catches everything else)
# ---------------------------------------------------------------------------

# Health check through the gateway: no authentication
resource "aws_apigatewayv2_route" "health" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.public.id}"
  authorization_type = "NONE"
}

# Login page for trying the flow in the browser (static HTML/JS).
# It must be reachable before the user has a token, so no authentication.
resource "aws_apigatewayv2_route" "pages" {
  for_each = toset(["GET /", "GET /callback"])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.public.id}"
  authorization_type = "NONE"
}

# Everything else (e.g. /me) requires a valid JWT
resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.protected.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# The $default stage serves the API at the root path (no /stage prefix)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true # publish route changes automatically
}
