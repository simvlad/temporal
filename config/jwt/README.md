# Local JWT Development Setup

This document describes how to run Temporal server locally with JWT authentication enabled for testing the Real ID prototype.

## Overview

The setup uses:
- A local JWKS server (Python HTTP server on port 8180)
- RSA key pair for signing/verifying JWTs
- Custom config file `development-jwt.yaml` with authorization enabled

## Files

| File | Description |
|------|-------------|
| `config/development-jwt.yaml` | Server config with JWT auth enabled |
| `config/jwt/setup-keys.sh` | Generates RSA key pair and JWKS (called automatically) |
| `config/jwt/generate-token.sh` | Helper script to generate test JWTs |
| `config/jwt/.gitignore` | Ignores generated files (private-key.pem, .well-known/) |

**Generated files** (not checked in, created by `setup-keys.sh`):
| File | Description |
|------|-------------|
| `config/jwt/private-key.pem` | RSA private key for signing test JWTs |
| `config/jwt/.well-known/jwks.json` | JWKS file with RSA public key |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make start-jwks-server` | Start Python HTTP server serving JWKS on port 8180 |
| `make stop-jwks-server` | Stop the JWKS server |
| `make start-jwt` | Start Temporal with JWT auth (no `--allow-no-auth` flag) |

## Usage

### 1. Start the JWKS Server

In a separate terminal:

```bash
make start-jwks-server
```

This automatically:
1. Generates RSA key pair if not present (`setup-keys.sh`)
2. Creates JWKS file from the public key
3. Starts HTTP server on port 8180

The JWKS is served at `http://localhost:8180/.well-known/jwks.json`.

### 2. Start Temporal with JWT Auth

In another terminal:

```bash
make start-jwt
```

Note: Unlike other `start-*` targets, this does NOT use the `--allow-no-auth` flag, so authentication is enforced.

### 3. Generate Test JWTs

```bash
# Default: test-user@example.com with system:admin
./config/jwt/generate-token.sh

# Custom subject with system:admin
./config/jwt/generate-token.sh alice@company.com

# Custom subject with namespace permission
./config/jwt/generate-token.sh alice@company.com default:admin

# Multiple permissions
./config/jwt/generate-token.sh alice@company.com system:admin default:writer
```

### 4. Use the Token

```bash
TOKEN=$(./config/jwt/generate-token.sh alice@example.com default:admin)

# With temporal CLI (if it supports Bearer auth)
temporal workflow list --address localhost:7233 # TODO: add auth header

# With curl (HTTP API)
curl -H "Authorization: Bearer $TOKEN" http://localhost:7243/api/v1/namespaces
```

## JWT Structure

The generated tokens have this structure:

**Header:**
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "test-key-1"
}
```

**Payload:**
```json
{
  "sub": "alice@example.com",
  "permissions": ["default:admin"],
  "iat": 1234567890,
  "exp": 1234571490
}
```

- `sub` - Subject claim, used as the Real ID actor (`jwt/<subject>`)
- `permissions` - Array of `<namespace>:<role>` or `system:<role>` strings
- `iat` - Issued at timestamp
- `exp` - Expiration timestamp (1 hour from issuance)

## Configuration Details

The `development-jwt.yaml` config adds this authorization section under `global:`:

```yaml
global:
  authorization:
    authorizer: "default"
    claimMapper: "default"
    jwtKeyProvider:
      keySourceURIs:
        - "http://localhost:8180/.well-known/jwks.json"
      refreshInterval: "1m"
```

## Verifying Real ID Flow

With JWT auth enabled, when you make authenticated requests:

1. JWT is validated against the JWKS public key
2. `defaultClaimMapper` extracts claims from the JWT
3. `defaultAuthorizer` computes the actor as `jwt/<subject>`
4. Actor is stored in context and propagated to history events

Look for `[Real ID]` log lines in the server output to trace the flow.

## Troubleshooting

### "Request unauthorized" errors

1. Ensure JWKS server is running: `curl http://localhost:8180/.well-known/jwks.json`
2. Check token expiration (tokens expire after 1 hour)
3. Verify permissions match the namespace you're accessing

### JWKS server won't start

Check if port 8180 is already in use:
```bash
lsof -i :8180
make stop-jwks-server
```

### Token signature verification fails

Ensure the JWKS public key matches the private key used for signing:
```bash
# Extract public key from private key
openssl rsa -in config/jwt/private-key.pem -pubout

# Compare with JWKS 'n' (modulus) value
```

### Regenerate keys

To force regeneration of keys (e.g., after manual edits):
```bash
rm -rf config/jwt/private-key.pem config/jwt/.well-known
make start-jwks-server  # Will regenerate both files
```
