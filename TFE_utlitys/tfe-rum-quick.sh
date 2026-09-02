#!/usr/bin/env bash
#
# tfe-rum-quick.sh
# 60-second RUM total from TFE. Use when you just need the headline number.
# For the full per-workspace breakdown and reconciliation, use tfe_rum_report.py
#
# Usage:
#   export TFE_TOKEN="xxxxxxxx.atlasv1.xxxxxxxx"
#   ./tfe-rum-quick.sh tfe.example.com my-org
#
# Requires: curl, jq

set -euo pipefail

HOST="${1:-}"
ORG="${2:-}"
PAGE_SIZE=100

[[ -z "${HOST}" || -z "${ORG}" ]] && { echo "Usage: $0 <tfe-host> <org-name>" >&2; exit 1; }
[[ -z "${TFE_TOKEN:-}" ]] && { echo "ERROR: TFE_TOKEN not set." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq required." >&2; exit 1; }

HOST="${HOST#https://}"; HOST="${HOST%/}"

auth=(--header "Authorization: Bearer ${TFE_TOKEN}"
      --header "Content-Type: application/vnd.api+json")

# ---------------------------------------------------------------------------
# 1. Explorer API - per-workspace RUM (TFE v202503-1+)
# ---------------------------------------------------------------------------
echo "== Explorer API (current RUM) =="
explorer_tmp="$(mktemp)"; trap 'rm -f "${explorer_tmp}"' EXIT
page=1; explorer_ok=0

while :; do
  resp="$(curl -sS "${auth[@]}" \
    "https://${HOST}/api/v2/organizations/${ORG}/explorer?type=workspaces&page%5Bsize%5D=${PAGE_SIZE}&page%5Bnumber%5D=${page}")" || break

  if echo "${resp}" | jq -e '.errors' >/dev/null 2>&1; then
    echo "  unavailable: $(echo "${resp}" | jq -r '.errors[0].detail // .errors[0].title')"
    break
  fi

  # Pick whichever key mentions "rum" - field name varies by TFE version
  echo "${resp}" | jq -r '
    .data[]?.attributes
    | (to_entries | map(select(.key|test("rum";"i"))) | .[0].value // empty) as $rum
    | select($rum != null)
    | "\(.workspace_name // .name)\t\($rum)"
  ' >> "${explorer_tmp}" || true

  explorer_ok=1
  next="$(echo "${resp}" | jq -r '.meta.pagination["next-page"] // empty')"
  [[ -z "${next}" ]] && break
  page="${next}"
done

if [[ "${explorer_ok}" == "1" && -s "${explorer_tmp}" ]]; then
  awk -F'\t' '{s+=$2; n++} END {printf "  workspaces: %d\n  TOTAL RUM : %d\n", n, s}' "${explorer_tmp}"
  echo "  top 10:"
  sort -t$'\t' -k2 -rn "${explorer_tmp}" | head -10 | awk -F'\t' '{printf "    %-45s %8d\n", $1, $2}'
else
  echo "  no RUM data returned (TFE may predate v202503-1)"
fi

# ---------------------------------------------------------------------------
# 2. Workspaces API resource-count - always available, good cross-check
# ---------------------------------------------------------------------------
echo ""
echo "== Workspaces API (resource-count cross-check) =="
ws_tmp="$(mktemp)"; trap 'rm -f "${explorer_tmp}" "${ws_tmp}"' EXIT
page=1

while :; do
  resp="$(curl -sS "${auth[@]}" \
    "https://${HOST}/api/v2/organizations/${ORG}/workspaces?page%5Bsize%5D=${PAGE_SIZE}&page%5Bnumber%5D=${page}")"

  if echo "${resp}" | jq -e '.errors' >/dev/null 2>&1; then
    echo "  ERROR: $(echo "${resp}" | jq -r '.errors[0].detail // .errors[0].title')" >&2
    exit 1
  fi

  echo "${resp}" | jq -r '.data[] | "\(.attributes.name)\t\(.attributes["resource-count"] // 0)"' >> "${ws_tmp}"

  next="$(echo "${resp}" | jq -r '.meta.pagination["next-page"] // empty')"
  [[ -z "${next}" ]] && break
  page="${next}"
done

awk -F'\t' '{s+=$2; n++} END {printf "  workspaces: %d\n  TOTAL      : %d\n  average    : %.1f\n", n, s, (n?s/n:0)}' "${ws_tmp}"
echo "  top 10:"
sort -t$'\t' -k2 -rn "${ws_tmp}" | head -10 | awk -F'\t' '{printf "    %-45s %8d\n", $1, $2}'

echo ""
echo "  empty workspaces (0 resources): $(awk -F'\t' '$2==0' "${ws_tmp}" | wc -l | tr -d ' ')"
