#!/usr/bin/env bash
#
# parse_k8s.sh — parse Kubernetes manifests (multi-doc YAML).
# Resources: each kind/name. Edges: Ingress->Service, Service->Deployment.
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

ip_parse_k8s() {
  local dir="${1:-.}"
  local files=()
  local f
  for f in "$dir"/*.yaml "$dir"/*.yml; do
    [ -e "$f" ] || continue
    grep -qiE '^[[:space:]]*kind:' "$f" 2>/dev/null && files+=("$f")
  done
  [ "${#files[@]}" -eq 0 ] && return 1

  IP_RAW=$(cat "${files[@]}" 2>/dev/null)

  # Per-document record:
  #   R <doc> <kind> <name> <app> <svcrefs...>
  local parsed
  parsed=$(printf '%s\n---\n' "$IP_RAW" | awk '
    BEGIN { doc = 0 }
    { sub(/\r$/, "") }
    /^---[ \t]*$/ { doc++; metapend = 0; insvc = 0; next }
    {
      line = $0
      if (line ~ /^kind:/) { k = line; sub(/^kind:[ \t]*/, "", k); gsub(/[ \t]/, "", k); kind[doc] = k }
      if (line ~ /^metadata:/) { metapend = 1 }
      if (metapend && line ~ /^[ \t]+name:/) {
        nm = line; sub(/.*name:[ \t]*/, "", nm); gsub(/["'\'']/, "", nm); gsub(/[ \t]/, "", nm)
        if (name[doc] == "") name[doc] = nm
        metapend = 0
      }
      if (line ~ /app:[ \t]*[^ \t]/) {
        a = line; sub(/.*app:[ \t]*/, "", a); gsub(/["'\'']/, "", a); gsub(/[ \t]/, "", a)
        if (app[doc] == "") app[doc] = a
      }
      # Ingress backend service references (both v1 and v1beta1 styles)
      if (line ~ /serviceName:/) {
        s = line; sub(/.*serviceName:[ \t]*/, "", s); gsub(/["'\'']/, "", s); gsub(/[ \t]/, "", s)
        svc[doc] = svc[doc] " " s
      }
      if (line ~ /^[ \t]+service:[ \t]*$/) { insvc = 1; next }
      if (insvc && line ~ /name:/) {
        s = line; sub(/.*name:[ \t]*/, "", s); gsub(/["'\'']/, "", s); gsub(/[ \t]/, "", s)
        svc[doc] = svc[doc] " " s; insvc = 0
      }
    }
    END {
      for (d = 0; d <= doc; d++) {
        if (kind[d] != "")
          print "R\t" d "\t" kind[d] "\t" name[d] "\t" app[d] "\t" svc[d]
      }
    }
  ')

  declare -A docid=()       # doc index -> resource id
  declare -A appToDeploy=() # app label -> deployment doc id
  declare -A nameToSvc=()   # service name -> service doc id
  declare -A docKind=()
  declare -A docApp=()
  declare -A docSvcrefs=()
  local tag doc kind name app svcrefs cat

  while IFS=$'\t' read -r tag doc kind name app svcrefs; do
    [ "$tag" = "R" ] || continue
    [ -z "$name" ] && name="$kind"
    cat=$(ip_cat_for_type "$kind")
    local meta="kind=$kind"
    [ -n "$app" ] && meta="$meta;app=$app"
    ip_add_resource "$kind" "$name" "$cat" "$meta"
    docid["$doc"]="$IP_LAST_ID"
    docKind["$doc"]="$kind"
    docApp["$doc"]="$app"
    docSvcrefs["$doc"]="$svcrefs"

    local lk; lk=$(printf '%s' "$kind" | tr '[:upper:]' '[:lower:]')
    case "$lk" in
      service) [ -n "$name" ] && nameToSvc["$name"]="$IP_LAST_ID" ;;
      deployment|statefulset|daemonset|replicaset)
        [ -n "$app" ] && appToDeploy["$app"]="$IP_LAST_ID" ;;
    esac
  done <<< "$parsed"

  # Build edges
  for doc in "${!docid[@]}"; do
    local lk; lk=$(printf '%s' "${docKind[$doc]}" | tr '[:upper:]' '[:lower:]')
    case "$lk" in
      service)
        local app="${docApp[$doc]}"
        if [ -n "$app" ] && [ -n "${appToDeploy[$app]:-}" ]; then
          ip_add_edge "${docid[$doc]}" "${appToDeploy[$app]}"
        fi
        ;;
      ingress)
        local s
        for s in ${docSvcrefs[$doc]}; do
          [ -n "${nameToSvc[$s]:-}" ] && ip_add_edge "${docid[$doc]}" "${nameToSvc[$s]}"
        done
        ;;
    esac
  done

  return 0
}
