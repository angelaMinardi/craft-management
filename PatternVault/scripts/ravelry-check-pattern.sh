#!/usr/bin/env bash
#
# Troubleshoot Ravelry pattern API: see response shape and whether pdf_url / free_pdf_url exist.
# Uses Basic auth (RAVELRY_ACCESS_KEY + RAVELRY_PERSONAL_KEY). Get these from:
#   https://www.ravelry.com/pro/developer — "Personal Access Token" / API keys.
#
# Usage:
#   export RAVELRY_ACCESS_KEY=your_access_key
#   export RAVELRY_PERSONAL_KEY=your_personal_key
#   ./scripts/ravelry-check-pattern.sh [PATTERN_ID]
#
# Pattern ID: numeric (e.g. from a Ravelry pattern URL or from your app's data).
# If omitted, uses a known test ID (e.g. 124400).
#

set -e
PATTERN_ID="${1:-124400}"
BASE="https://api.ravelry.com"

if [[ -z "$RAVELRY_ACCESS_KEY" || -z "$RAVELRY_PERSONAL_KEY" ]]; then
  echo "Set RAVELRY_ACCESS_KEY and RAVELRY_PERSONAL_KEY in the environment."
  echo "Get them from https://www.ravelry.com/pro/developer (Personal Access Token)."
  exit 1
fi

AUTH=$(echo -n "${RAVELRY_ACCESS_KEY}:${RAVELRY_PERSONAL_KEY}" | base64)
URL="${BASE}/patterns.json?ids=${PATTERN_ID}"

echo "GET $URL"
echo "---"
RESP=$(curl -s -w "\n%{http_code}" -H "Authorization: Basic $AUTH" "$URL")
HTTP_CODE=$(echo "$RESP" | tail -1)
HTTP_BODY=$(echo "$RESP" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "HTTP $HTTP_CODE"
  echo "$HTTP_BODY" | head -c 500
  exit 1
fi

# Detect patterns payload type and show summary
if command -v jq &>/dev/null; then
  echo "Response structure:"
  echo "$HTTP_BODY" | jq -r '
    if .patterns then
      ".patterns type: " + (.patterns | type),
      (.patterns | if type == "array" then " .patterns[0] keys: " + (if length > 0 then (.[0] | keys | join(", ")) else "(empty)" end) else " .patterns (object) first key: " + (keys[0] // "(none)") end)
    else
      "Top-level keys: " + (keys | join(", "))
    end
  ' 2>/dev/null || true
  # First pattern's pdf fields (array or object with one key)
  P=$(echo "$HTTP_BODY" | jq -c '.patterns' 2>/dev/null)
  if [[ -n "$P" && "$P" != "null" ]]; then
    FIRST=$(echo "$P" | jq -c 'if type == "array" then .[0] else .[keys[0]] end' 2>/dev/null)
    if [[ -n "$FIRST" && "$FIRST" != "null" ]]; then
      INNER=$(echo "$FIRST" | jq -c 'if .pattern then .pattern else . end' 2>/dev/null)
      echo ""
      echo "First pattern (or .pattern wrapper):"
      echo "$INNER" | jq -r '"  id: " + (.id | tostring), "  pdf_url: " + (.pdf_url // "(missing)"), "  free_pdf_url: " + (.free_pdf_url // "(missing)")' 2>/dev/null || echo "$INNER"
    fi
  fi
  echo ""
  echo "Raw .patterns (first 800 chars):"
  echo "$HTTP_BODY" | jq -c '.patterns' 2>/dev/null | head -c 800
  echo ""
else
  echo "Install jq for a structured summary. Raw response (first 1500 chars):"
  echo "$HTTP_BODY" | head -c 1500
fi
