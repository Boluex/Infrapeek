#!/usr/bin/env bash
#
# parse_terraform.sh — extract resource blocks + references from *.tf files.
# Populates the shared model (IP_RES_*, IP_EDGES) via ip_add_resource/ip_add_edge.
#

# --- guard: provide the model helpers when sourced standalone ----------------
if ! declare -F ip_add_resource >/dev/null 2>&1; then
  declare -a IP_RES_ID=(); declare -A IP_RES_TYPE=() IP_RES_NAME=() IP_RES_CAT=() IP_RES_META=()
  declare -a IP_EDGES=(); IP_RES_N=0; IP_LAST_ID=""; IP_RAW=""
  ip_add_resource(){ local id="r${IP_RES_N}"; IP_RES_N=$((IP_RES_N+1)); IP_RES_ID+=("$id")
    IP_RES_TYPE["$id"]="$1"; IP_RES_NAME["$id"]="$2"; IP_RES_CAT["$id"]="${3:-other}"; IP_RES_META["$id"]="${4:-}"; IP_LAST_ID="$id"; }
  ip_add_edge(){ [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && IP_EDGES+=("$1|$2"); return 0; }
  ip_cat_for_type(){ echo other; }
fi
# -----------------------------------------------------------------------------

ip_parse_terraform() {
  local dir="${1:-.}"
  local files=()
  local f
  for f in "$dir"/*.tf; do [ -e "$f" ] && files+=("$f"); done
  [ "${#files[@]}" -eq 0 ] && return 1

  IP_RAW=$(cat "${files[@]}" 2>/dev/null)

  # Pass 1: walk the HCL, emitting tab-separated records:
  #   R <type> <name>        for each resource block
  #   B <type.name> <line>   for every line inside that block (used for refs)
  local parsed
  parsed=$(printf '%s\n' "$IP_RAW" | awk '
    function emit_res(line,   seg,a,t,nm) {
      if (match(line, /"[^"]+"[ \t]+"[^"]+"/)) {
        seg = substr(line, RSTART, RLENGTH); gsub(/"/, "", seg);
        split(seg, a, /[ \t]+/); t = a[1]; nm = a[2];
        cur = t "." nm;
        print "R\t" t "\t" nm;
      }
    }
    {
      line = $0
      if (depth == 0 && line ~ /^[ \t]*resource[ \t]+"/) emit_res(line)
      o = gsub(/{/, "{", line); c = gsub(/}/, "}", line)
      if (cur != "") print "B\t" cur "\t" $0
      depth += o - c
      if (depth <= 0) { depth = 0; cur = "" }
    }
  ')

  declare -A keyid=()
  declare -A bodies=()
  local tag a b cat

  while IFS=$'\t' read -r tag a b; do
    case "$tag" in
      R)
        cat=$(ip_cat_for_type "$a")
        ip_add_resource "$a" "$b" "$cat"
        keyid["$a.$b"]="$IP_LAST_ID"
        ;;
      B)
        bodies["$a"]+="$b"$'\n'
        ;;
    esac
  done <<< "$parsed"

  # Pass 2: build edges from references (block body mentions another type.name)
  local k other
  for k in "${!keyid[@]}"; do
    local body="${bodies[$k]}"
    for other in "${!keyid[@]}"; do
      [ "$other" = "$k" ] && continue
      if printf '%s' "$body" | grep -qF "$other"; then
        # k references other  =>  k depends on / points to other
        ip_add_edge "${keyid[$k]}" "${keyid[$other]}"
      fi
    done
  done

  return 0
}
