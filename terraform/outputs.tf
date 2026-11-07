# Base URL of the API, e.g. https://xxxx.execute-api.ap-northeast-1.amazonaws.com
output "api_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

# Used by `make push` as the docker push target
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# Used by the Makefile for creating users and requesting tokens
output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

# The `iss` claim expected in tokens; also where the signing keys are published (/.well-known/jwks.json)
output "cognito_issuer" {
  value = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_ui_base_url" {
  value = local.cognito_base_url
}

# Open this URL in a browser to try the login flow (PKCE) end to end
output "app_url" {
  value = "${aws_apigatewayv2_api.main.api_endpoint}/"
}
