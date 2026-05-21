#!/usr/bin/env bash
# Smoke test for the Flue Skill Drift Detector agent.
#
# WARNING: This script calls the Anthropic API and WILL spend credits.
# Estimated cost per run: $0.20 - $1.00 depending on PR volume.
#
# Usage:
#   ANTHROPIC_API_KEY=... GH_TOKEN=... ./scripts/test-flue-detector.sh <skill_name> <sdk_repo> <pr_number>
#   ANTHROPIC_API_KEY=... GH_TOKEN=... ./scripts/test-flue-detector.sh --fixture
#
#
# NOTE: The fixture PR is synthetic and may not resolve to a real upstream PR, so the detector
# may emit skip due to unavailable diff data.

set -euo pipefail

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set}"
: "${GH_TOKEN:=${GITHUB_TOKEN:-}}"
if [ -z "${GH_TOKEN}" ]; then
  echo "Error: GH_TOKEN or GITHUB_TOKEN must be set (the Detector uses 'gh' CLI for PR lookups)." >&2
  exit 1
fi
export GH_TOKEN

FIXTURE="scripts/fixtures/flue-detector-pr.json"
OUT=/tmp/flue-detector-result.json
RAW=/tmp/flue-detector-raw.log

if [ "${1:-}" = "--fixture" ]; then
  if [ ! -f "$FIXTURE" ]; then
    echo "Fixture not found: $FIXTURE" >&2
    exit 1
  fi
  PAYLOAD=$(jq -c . "$FIXTURE")
else
  if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <skill_name> <sdk_repo> <pr_number>" >&2
    echo "   or: $0 --fixture" >&2
    exit 1
  fi

  SKILL_NAME="$1"
  SDK_REPO="$2"
  PR_NUMBER="$3"

  PAYLOAD=$(jq -c -n \
    --arg skill_name "$SKILL_NAME" \
    --arg sdk_repo "$SDK_REPO" \
    --argjson pr_number "$PR_NUMBER" \
    --arg pr_url "https://github.com/${SDK_REPO}/pull/${PR_NUMBER}" \
    '{skill_name:$skill_name,sdk_repo:$sdk_repo,pr_number:$pr_number,pr_url:$pr_url}')
fi

echo "=== Flue Detector smoke test ==="
echo "Agent:   skill-drift-detector"
echo "Model:   anthropic/claude-opus-4-6 (live API call — costs money)"
echo "Payload: $PAYLOAD"
echo "Output:  $OUT"
echo
read -rp "Continue? [y/N] " yn
[[ "$yn" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }

# Flue CLI mixes build messages ("[flue] Building:", etc.) into stdout BEFORE
# the agent's JSON result. Capture the raw stream, then extract the trailing
# JSON object (everything from the first line starting with '{').
npx flue run skill-drift-detector --target node \
  --id "smoketest-detector-$(date +%s)" \
  --payload "$PAYLOAD" \
  > "$RAW"
sed -n '/^{/,$p' "$RAW" > "$OUT"

echo
echo "=== Raw output: $RAW ==="
echo "=== Parsed JSON: $OUT ==="

echo
echo "=== Result ==="
jq . "$OUT"

echo

# Quick schema sanity check
if jq -e '.actions and (.actions | type == "array") and (.summary | type == "string")' "$OUT" > /dev/null; then
  echo "PASS: output has 'actions' array and 'summary' string"
else
  echo "FAIL: output does not match expected DetectorOutput schema" >&2
  exit 1
fi
