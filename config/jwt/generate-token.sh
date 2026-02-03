#!/bin/bash
# Generate a test JWT signed with the local private key
# Usage: ./generate-token.sh [subject] [permissions...]
#
# Examples:
#   ./generate-token.sh                                    # Default: test-user@example.com with system:admin
#   ./generate-token.sh alice@company.com                  # Custom subject with system:admin
#   ./generate-token.sh alice@company.com default:admin    # Custom subject with namespace permission
#   ./generate-token.sh alice@company.com system:admin default:writer  # Multiple permissions
#
# The generated JWT has the following structure:
#   Header: {"alg": "RS256", "typ": "JWT", "kid": "test-key-1"}
#   Payload: {"sub": "<subject>", "permissions": ["<perm1>", ...], "iat": <now>, "exp": <now+1h>}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_KEY="$SCRIPT_DIR/private-key.pem"

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key not found at $PRIVATE_KEY" >&2
    exit 1
fi

# Default values
SUBJECT="${1:-test-user@example.com}"
shift 2>/dev/null || true

# Collect permissions (default to system:admin if none specified)
if [ $# -eq 0 ]; then
    PERMISSIONS='["system:admin"]'
else
    PERMISSIONS=$(printf '%s\n' "$@" | jq -R . | jq -s .)
fi

# Get current timestamp and expiration (1 hour from now)
NOW=$(date +%s)
EXP=$((NOW + 3600))

# Create header (base64url encoded)
HEADER='{"alg":"RS256","typ":"JWT","kid":"test-key-1"}'
HEADER_B64=$(echo -n "$HEADER" | base64 | tr '+/' '-_' | tr -d '=')

# Create payload (base64url encoded)
PAYLOAD=$(cat <<EOF
{"sub":"$SUBJECT","permissions":$PERMISSIONS,"iat":$NOW,"exp":$EXP}
EOF
)
PAYLOAD_B64=$(echo -n "$PAYLOAD" | base64 | tr '+/' '-_' | tr -d '=')

# Create signature
SIGNATURE=$(echo -n "${HEADER_B64}.${PAYLOAD_B64}" | \
    openssl dgst -sha256 -sign "$PRIVATE_KEY" | \
    base64 | tr '+/' '-_' | tr -d '=')

# Output the complete JWT
echo "${HEADER_B64}.${PAYLOAD_B64}.${SIGNATURE}"
