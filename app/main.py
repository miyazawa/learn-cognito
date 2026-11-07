import base64
import json
import os
from pathlib import Path

from fastapi import FastAPI, Header
from fastapi.responses import HTMLResponse

app = FastAPI(title="cognito-learning-app")

# Login page. The PKCE handling and token exchange are done by the JavaScript in
# this file, running in the browser; the server only serves the page.
_INDEX_TEMPLATE = (Path(__file__).parent / "index.html").read_text(encoding="utf-8")


def decode_jwt_payload(authorization: str | None) -> dict:
    """Decode the payload of the JWT in the Authorization header (no signature check).

    The signature, expiry, issuer and audience have already been verified by the
    API Gateway JWT authorizer, so this only reads the claims. It is used here to
    show what is inside the token; a service that is reachable without API Gateway
    must verify the token itself.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        return {}
    token = authorization.split(" ", 1)[1]
    try:
        # A JWT is "header.payload.signature"; each part is base64url-encoded
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)  # restore the stripped base64 padding
        return json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}


def _render_page() -> HTMLResponse:
    # Inject the Cognito settings (provided as environment variables by the ECS
    # task definition) into the page where the placeholder is.
    config = {
        "cognitoBaseUrl": os.environ.get("COGNITO_BASE_URL", ""),
        "clientId": os.environ.get("COGNITO_CLIENT_ID", ""),
    }
    html = _INDEX_TEMPLATE.replace("__CONFIG__", json.dumps(config))

    # no-store: never cache a page that may be shown after login
    return HTMLResponse(html, headers={"Cache-Control": "no-store"})


@app.get("/health")
def health():
    # No authentication. Used by the ALB health check and by the public
    # /health route on API Gateway.
    return {"status": "ok"}


# "/" and "/callback" are public routes on API Gateway (no JWT is needed to see
# the login page). Both return the same page: when the URL is /callback?code=...,
# the JavaScript exchanges the code for tokens.
@app.get("/", response_class=HTMLResponse)
def index():
    return _render_page()


@app.get("/callback", response_class=HTMLResponse)
def callback():
    return _render_page()


# Protected: API Gateway only forwards requests that carry a valid JWT.
@app.get("/me")
def me(
    x_user_sub: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
):
    claims = decode_jwt_payload(authorization)
    return {
        # Set by API Gateway's parameter mapping from the verified token.
        # Clients cannot spoof it because the gateway overwrites the header.
        "sub_from_gateway_header": x_user_sub,
        # Decoded JWT payload. The contents differ by token type
        # (ID token: email, aud; access token: client_id, scope).
        "token_use": claims.get("token_use"),
        "claims": claims,
    }
