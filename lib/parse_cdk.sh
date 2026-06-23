#!/usr/bin/env bash
#
# parse_cdk.sh — run `cdk synth` and parse the CloudFormation JSON output.
# Uses jq when available; otherwise falls back to grep/awk.
#

# --- guard ------------------------------------------------------------------
if ! declare -F ip_add_resource >/dev/null 2>&1; then
  declare -a IP_RES_ID=(); declare -A IP_RES_TYPE=() IP_RES_NAME=() IP_RES_CAT=() IP_RES_META=()
  declare -a IP_EDGES=(); IP_RES_N=0; IP_LAST_ID=""; IP_RAW=""
  ip_add_resource(){ local id="r${IP_RES_N}"; IP_RES_N=$((IP_RES_N+1)); IP_RES_ID+=("$id")
    IP_RES_TYPE["$id"]="$1"; IP_RES_NAME["$id"]="$2"; IP_RES_CAT["$id"]="${3:-other}"; IP_RES_META["$id"]="${4:-}"; IP_LAST_ID="$id"; }
  ip_add_edge(){ [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && IP_EDGES+=("$1|$2"); return 0; }
  ip_cat_for_type(){ echo other; }
fi
# ----------------------------------------------------------------------------

# AWS::Lambda::Function  ->  aws_lambda_function  (reuses our category/cost maps)
ip_cfn_to_tftype() {
  local t; t=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  t="${t//::/_}"        # aws_lambda_function
  printf '%s' "$t"
}

ip_parse_cdk() {
  local dir="${1:-.}"
  local json=""

  # 1. Try a fresh synth (quiet). 2. Fall back to an existing cdk.out template.
  if command -v cdk >/dev/null 2>&1; then
    json=$( (cd "$dir" && cdk synth --quiet) 2>/dev/null )
  fi
  if [ -z "$json" ]; then
    local tmpl
    tmpl=$(find "$dir/cdk.out" -maxdepth 1 -name '*.template.json' 2>/dev/null | head -n1)
    [ -n "$tmpl" ] && json=$(cat "$tmpl" 2>/dev/null)
  fi
  if [ -z "$json" ]; then
    echo "infrapeek: 'cdk synth' produced no output (is the AWS CDK installed and the app buildable?)" >&2
    return 1
  fi

  IP_RAW="$json"
  declare -A keyid=()

  if command -v jq >/dev/null 2>&1; then
    # logical id <tab> CFN type
    local line lid cfn tftype cat
    while IFS=$'\t' read -r lid cfn; do
      [ -z "$lid" ] && continue
      tftype=$(ip_cfn_to_tftype "$cfn")
      cat=$(ip_cat_for_type "$tftype")
      ip_add_resource "$tftype" "$lid" "$cat" "cfn=$cfn"
      keyid["$lid"]="$IP_LAST_ID"
    done < <(printf '%s' "$json" | jq -r '.Resources // {} | to_entries[] | "\(.key)\t\(.value.Type)"' 2>/dev/null)

    # edges: any logical id referenced inside another resource's body
    local k other body
    for k in "${!keyid[@]}"; do
      body=$(printf '%s' "$json" | jq -c ".Resources[\"$k\"]" 2>/dev/null)
      for other in "${!keyid[@]}"; do
        [ "$other" = "$k" ] && continue
        if printf '%s' "$body" | grep -qF "\"$other\""; then
          ip_add_edge "${keyid[$k]}" "${keyid[$other]}"
        fi
      done
    done
  else
    # jq-less fallback: pull "Logical": { "Type": "AWS::..." } pairs.
    local parsed
    parsed=$(printf '%s\n' "$json" | awk '
      { for (i = 1; i <= NF; i++) ; }
      /"[A-Za-z0-9]+"[ \t]*:[ \t]*{[ \t]*$/ {
        lid = $0; sub(/^[ \t]*"/, "", lid); sub(/".*/, "", lid); cand = lid
      }
      /"Type"[ \t]*:[ \t]*"AWS::/ {
        ty = $0; sub(/.*"Type"[ \t]*:[ \t]*"/, "", ty); sub(/".*/, "", ty)
        if (cand != "") { print cand "\t" ty; cand = "" }
      }
    ')
    local lid cfn tftype cat
    while IFS=$'\t' read -r lid cfn; do
      [ -z "$lid" ] && continue
      tftype=$(ip_cfn_to_tftype "$cfn")
      cat=$(ip_cat_for_type "$tftype")
      ip_add_resource "$tftype" "$lid" "$cat" "cfn=$cfn"
    done <<< "$parsed"
  fi

  return 0
}
