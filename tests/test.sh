#!/usr/bin/env bash
#
# test.sh — basic end-to-end tests for infrapeek against the fixtures.
# Run:  ./tests/test.sh
#
set -o pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BIN="$ROOT/infrapeek"
FIX="$HERE/fixtures"

export INFRAPEEK_NO_PAUSE=1   # never block on the ENTER prompt
export NO_COLOR=1             # deterministic, colourless output

pass=0; fail=0
grn=$'\033[32m'; red=$'\033[31m'; rst=$'\033[0m'

# check "description" "needle" <<< "$output"
# Reads stdin via here-string so it stays in the current shell (counters persist).
check() {
  local desc="$1" needle="$2" out; out=$(cat)
  if printf '%s' "$out" | grep -qF "$needle"; then
    printf '  %s✓%s %s\n' "$grn" "$rst" "$desc"; pass=$((pass+1))
  else
    printf '  %s✗%s %s\n' "$red" "$rst" "$desc"; fail=$((fail+1))
    printf '      expected to find: %s\n' "$needle"
  fi
}

ok() { printf '  %s✓%s %s\n' "$grn" "$rst" "$1"; pass=$((pass+1)); }
no() { printf '  %s✗%s %s\n' "$red" "$rst" "$1"; fail=$((fail+1)); }

section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------------------
section "meta"
check "prints version" "infrapeek v" <<< "$("$BIN" --version)"
check "prints help"    "USAGE"       <<< "$("$BIN" --help)"

# ---------------------------------------------------------------------------
section "detection (sourced)"
# shellcheck source=/dev/null
source "$ROOT/lib/detect.sh"
[ "$(ip_detect "$FIX/terraform")" = "terraform" ] && ok "detects terraform" || no "detects terraform"
[ "$(ip_detect "$FIX/compose")"   = "compose" ]   && ok "detects compose"   || no "detects compose"
[ "$(ip_detect "$FIX/k8s")"       = "k8s" ]       && ok "detects k8s"       || no "detects k8s"

# ---------------------------------------------------------------------------
section "terraform fixture"
out=$("$BIN" "$FIX/terraform")
check "header shows Terraform"     "Terraform"           <<< "$out"
check "detects LocalStack"         "LocalStack"          <<< "$out"
check "lists lambda function"      "aws_lambda_function" <<< "$out"
check "lists dynamodb table"       "aws_dynamodb_table"  <<< "$out"
check "lists s3 bucket"            "aws_s3_bucket"       <<< "$out"
check "draws Internet entry point" "Internet"            <<< "$out"
check "warns about s3 versioning"  "versioning"          <<< "$out"

# ---------------------------------------------------------------------------
section "compose fixture"
out=$("$BIN" "$FIX/compose")
check "header shows Docker Compose" "Docker Compose" <<< "$out"
check "lists nginx service"         "nginx"          <<< "$out"
check "lists postgres service"      "postgres"       <<< "$out"
check "warns about a hard-coded secret" "secret"     <<< "$out"

# ---------------------------------------------------------------------------
section "k8s fixture"
out=$("$BIN" "$FIX/k8s")
check "header shows Kubernetes" "Kubernetes" <<< "$out"
check "lists Deployment"        "Deployment" <<< "$out"
check "lists Service"           "Service"    <<< "$out"
check "lists Ingress"           "Ingress"    <<< "$out"

# ---------------------------------------------------------------------------
section "forced format"
check "--format compose works" "Docker Compose" <<< "$("$BIN" --format compose "$FIX/compose")"

# ---------------------------------------------------------------------------
printf '\n────────────────────────────\n'
printf 'passed: %s   failed: %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
