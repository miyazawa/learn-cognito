locals {
  # Register the pages served from API Gateway as the OAuth callback / logout targets,
  # so the login flow can be tried in the browser. Cognito requires an exact match
  # with these registered URLs (HTTPS only, except http://localhost).
  callback_urls = concat(["${aws_apigatewayv2_api.main.api_endpoint}/callback"], var.callback_urls)
  logout_urls   = concat(["${aws_apigatewayv2_api.main.api_endpoint}/"], var.logout_urls)

  # Base URL of the Hosted UI and the OAuth2 endpoints (/oauth2/authorize, /oauth2/token, /logout)
  cognito_base_url = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

# The user directory. Issues the JWTs that API Gateway validates.
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Users sign in with their email address instead of a separate username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Allow `terraform destroy` to delete the pool (learning environment)
  deletion_protection = "INACTIVE"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # Password reset via verified email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# The application that is allowed to sign users in (the "audience" of the tokens)
resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client (browser/mobile apps cannot keep a secret); PKCE protects the code flow instead
  generate_secret = false

  # Auth flows for direct API calls (no Hosted UI):
  #   USER_PASSWORD_AUTH   - sends the password as-is; convenient for CLI testing, avoid in real apps
  #   USER_SRP_AUTH        - password never leaves the client; what Amplify-style SDKs use
  #   REFRESH_TOKEN_AUTH   - lets the client get new access/ID tokens with the refresh token
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Hosted UI: OAuth2 authorization code flow
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = local.callback_urls
  logout_urls                          = local.logout_urls

  # Short-lived access/ID tokens limit the damage of a leaked token;
  # the refresh token is used to renew them.
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Return a generic error for wrong user/password instead of revealing which users exist
  prevent_user_existence_errors = "ENABLED"
}

# Hosted UI domain. The name must be globally unique, so the account ID is appended.
# Note: the prefix cannot contain the reserved word "cognito".
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.domain_prefix}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}
