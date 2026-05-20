#!/usr/bin/env bash
#
# test-discovery.sh — validate an MCP server's OAuth discovery setup.
#
# Checks:
#   1. RFC 9728  — Protected Resource Metadata at /.well-known/oauth-protected-resource
#   2. RFC 8414  — Authorization Server Metadata at /.well-known/oauth-authorization-server
#   3. RFC 7591  — Dynamic Client Registration via the advertised registration_endpoint
#   4. The 401 + WWW-Authenticate response that kicks the whole flow off
#
# Usage:
#   ./test-discovery.sh https://api.your-app.com
#   ./test-discovery.sh https://api.your-app.com /mcp     # custom protected path
#
# Exit code 0 if every check passes, non-zero otherwise.

set -u

BASE_URL="${1:-}"
MCP_PATH="${2:-/mcp}"

if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <base-url> [mcp-path]"
  echo "example: $0 https://api.your-app.com /mcp"
  exit 2
fi

# Strip trailing slash for clean joins.
BASE_URL="${BASE_URL%/}"

# ANSI colours — fall back to plain if not a TTY.
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=''; GRN=''; YEL=''; DIM=''; BLD=''; RST=''
fi

pass=0
fail=0

ok()   { printf "  %s✓%s %s\n" "$GRN" "$RST" "$1"; pass=$((pass+1)); }
bad()  { printf "  %s✗%s %s\n" "$RED" "$RST" "$1"; fail=$((fail+1)); }
info() { printf "  %s·%s %s\n" "$DIM" "$RST" "$1"; }
head() { printf "\n%s%s%s\n" "$BLD" "$1" "$RST"; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "${RED}error:${RST} jq is required. Install with: brew install jq"
    exit 2
  fi
}
require_jq

# -----------------------------------------------------------------------------
# 1. 401 + WWW-Authenticate on the protected resource
# -----------------------------------------------------------------------------
head "[1/4] Protected resource returns 401 with WWW-Authenticate"
PROTECTED_URL="${BASE_URL}${MCP_PATH}"
info "GET ${PROTECTED_URL}"

resp_headers=$(curl -sS -i -o /dev/null -D - "$PROTECTED_URL" 2>/dev/null || true)
status_line=$(printf "%s" "$resp_headers" | head -n1)
www_auth=$(printf "%s" "$resp_headers" | grep -i '^www-authenticate:' || true)

if printf "%s" "$status_line" | grep -q '401'; then
  ok "responds with 401"
else
  bad "expected 401, got: $status_line"
fi

if [[ -n "$www_auth" ]]; then
  ok "WWW-Authenticate header present"
  rm_url=$(printf "%s" "$www_auth" | sed -nE 's/.*resource_metadata="?([^",]+)"?.*/\1/p')
  if [[ -n "$rm_url" ]]; then
    ok "resource_metadata URL advertised: $rm_url"
  else
    bad "WWW-Authenticate is missing resource_metadata=\"...\""
  fi
else
  bad "no WWW-Authenticate header — mcp-remote will not start discovery"
  rm_url="${BASE_URL}/.well-known/oauth-protected-resource"
  info "falling back to conventional URL: $rm_url"
fi

# -----------------------------------------------------------------------------
# 2. RFC 9728 — Protected Resource Metadata
# -----------------------------------------------------------------------------
head "[2/4] RFC 9728 — Protected Resource Metadata"
info "GET ${rm_url}"

rm_body=$(curl -sS "$rm_url" 2>/dev/null || true)
if ! printf "%s" "$rm_body" | jq -e . >/dev/null 2>&1; then
  bad "response is not valid JSON"
  printf "%s\n" "$rm_body" | head -n5
else
  ok "valid JSON"
  for field in resource authorization_servers; do
    if printf "%s" "$rm_body" | jq -e ".${field}" >/dev/null 2>&1; then
      ok "has \"${field}\""
    else
      bad "missing required field \"${field}\""
    fi
  done
  auth_server=$(printf "%s" "$rm_body" | jq -r '.authorization_servers[0] // empty')
  if [[ -n "$auth_server" ]]; then
    info "authorization_server: ${auth_server}"
  fi
fi

# -----------------------------------------------------------------------------
# 3. RFC 8414 — Authorization Server Metadata
# -----------------------------------------------------------------------------
head "[3/4] RFC 8414 — Authorization Server Metadata"
auth_server="${auth_server:-$BASE_URL}"
as_url="${auth_server%/}/.well-known/oauth-authorization-server"
info "GET ${as_url}"

as_body=$(curl -sS "$as_url" 2>/dev/null || true)
registration_endpoint=""
if ! printf "%s" "$as_body" | jq -e . >/dev/null 2>&1; then
  bad "response is not valid JSON"
else
  ok "valid JSON"
  for field in issuer authorization_endpoint token_endpoint; do
    if printf "%s" "$as_body" | jq -e ".${field}" >/dev/null 2>&1; then
      ok "has \"${field}\""
    else
      bad "missing required field \"${field}\""
    fi
  done

  # PKCE support
  if printf "%s" "$as_body" | jq -e '.code_challenge_methods_supported | index("S256")' >/dev/null 2>&1; then
    ok "advertises PKCE S256"
  else
    bad "does not advertise S256 in code_challenge_methods_supported"
  fi

  registration_endpoint=$(printf "%s" "$as_body" | jq -r '.registration_endpoint // empty')
  if [[ -n "$registration_endpoint" ]]; then
    ok "registration_endpoint advertised: ${registration_endpoint}"
  else
    bad "no registration_endpoint — RFC 7591 not supported (mcp-remote will fail)"
  fi
fi

# -----------------------------------------------------------------------------
# 4. RFC 7591 — Dynamic Client Registration
# -----------------------------------------------------------------------------
head "[4/4] RFC 7591 — Dynamic Client Registration"
if [[ -z "$registration_endpoint" ]]; then
  bad "skipping — no registration_endpoint to call"
else
  info "POST ${registration_endpoint}"
  reg_payload='{
    "client_name": "test-discovery-script",
    "redirect_uris": ["http://localhost:33418/callback"],
    "grant_types": ["authorization_code", "refresh_token"],
    "token_endpoint_auth_method": "none",
    "code_challenge_methods_supported": ["S256"]
  }'

  reg_body=$(curl -sS -X POST "$registration_endpoint" \
    -H "Content-Type: application/json" \
    -d "$reg_payload" 2>/dev/null || true)

  if ! printf "%s" "$reg_body" | jq -e . >/dev/null 2>&1; then
    bad "response is not valid JSON"
    printf "%s\n" "$reg_body" | head -n5
  else
    client_id=$(printf "%s" "$reg_body" | jq -r '.client_id // empty')
    if [[ -n "$client_id" ]]; then
      ok "returned client_id: ${client_id}"
    else
      bad "no client_id in response — registration rejected"
      printf "%s\n" "$reg_body" | jq . 2>/dev/null | head -n10
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
head "Summary"
printf "  %s%d passed%s · %s%d failed%s\n" "$GRN" "$pass" "$RST" "$RED" "$fail" "$RST"

if [[ "$fail" -gt 0 ]]; then
  echo
  echo "${YEL}Your server is not fully MCP-OAuth-compliant yet.${RST}"
  echo "Fix the failing checks above before pointing mcp-remote at it."
  exit 1
fi

echo
echo "${GRN}All discovery checks passed.${RST} mcp-remote should be able to connect."
exit 0
