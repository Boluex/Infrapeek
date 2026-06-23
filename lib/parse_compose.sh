#!/usr/bin/env bash
#
# parse_compose.sh — parse docker-compose.yml services, ports, depends_on.
#

# --- guard ------------------------------------------------------------------
if ! declare -F ip_add_resource >/dev/null 2>&1; then
  declare -a IP_RES_ID=(); declare -A IP_RES_TYPE=() IP_RES_NAME=() IP_RES_CAT=() IP_RES_META=()
  declare -a IP_EDGES=(); IP_RES_N=0; IP_LAST_ID=""; IP_RAW=""
  ip_add_resource(){ local id="r${IP_RES_N}"; IP_RES_N=$((IP_RES_N+1)); IP_RES_ID+=("$id")
    IP_RES_TYPE["$id"]="$1"; IP_RES_NAME["$id"]="$2"; IP_RES_CAT["$id"]="${3:-other}"; IP_RES_META["$id"]="${4:-}"; IP_LAST_ID="$id"; }
  ip_add_edge(){ [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && IP_EDGES+=("$1|$2"); return 0; }
fi
# ----------------------------------------------------------------------------

# category for a compose service, inferred from its image
ip_compose_cat() {
  local img; img=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$img" in
    *postgres*|*mysql*|*mariadb*|*mongo*|*redis*|*cassandra*|*couch*|*elastic*|*memcached*|*influx*) echo datastore ;;
    *nginx*|*traefik*|*caddy*|*haproxy*|*envoy*|*kong*|*httpd*|*apache*) echo gateway ;;
    *rabbitmq*|*kafka*|*nats*|*zookeeper*|*activemq*) echo queue ;;
    *) echo compute ;;
  esac
}

ip_parse_compose() {
  local dir="${1:-.}"
  local file=""
  local c
  for c in "$dir/docker-compose.yml" "$dir/docker-compose.yaml" \
           "$dir/compose.yml" "$dir/compose.yaml"; do
    [ -f "$c" ] && { file="$c"; break; }
  done
  [ -z "$file" ] && return 1

  IP_RAW=$(cat "$file" 2>/dev/null)

  # Emit records:  S <svc> | I <svc> <image> | P <svc> <port> | D <svc> <dep>
  local parsed
  parsed=$(printf '%s\n' "$IP_RAW" | awk '
    { sub(/\r$/, "") }
    /^services:[ \t]*$/        { inserv = 1; mode = ""; next }
    /^[^ \t#]/ && !/^services:/ { inserv = 0 }
    inserv {
      line = $0
      if (line ~ /^  [A-Za-z0-9._-]+:[ \t]*$/) {
        s = line; gsub(/[ \t:]/, "", s); cur = s; mode = ""; print "S\t" s; next
      }
      if (cur == "") next
      if (line ~ /^    image:/) {
        v = line; sub(/^    image:[ \t]*/, "", v); gsub(/["'\'']/, "", v); gsub(/[ \t]+$/, "", v)
        print "I\t" cur "\t" v; mode = ""; next
      }
      if (line ~ /^    depends_on:/) {
        mode = "dep"
        if (line ~ /\[/) {
          arr = line; sub(/.*\[/, "", arr); sub(/\].*/, "", arr); n = split(arr, a, /,/)
          for (i = 1; i <= n; i++) { gsub(/[ \t"'\'']/, "", a[i]); if (a[i] != "") print "D\t" cur "\t" a[i] }
          mode = ""
        }
        next
      }
      if (line ~ /^    ports:/) {
        mode = "port"
        if (line ~ /\[/) {
          arr = line; sub(/.*\[/, "", arr); sub(/\].*/, "", arr); n = split(arr, a, /,/)
          for (i = 1; i <= n; i++) { gsub(/[ \t"'\'']/, "", a[i]); if (a[i] != "") print "P\t" cur "\t" a[i] }
          mode = ""
        }
        next
      }
      if (line ~ /^    [A-Za-z0-9._-]+:/) { mode = ""; next }
      if (mode == "dep" && line ~ /^ *- /) {
        v = line; sub(/^[ \t]*-[ \t]*/, "", v); gsub(/["'\'']/, "", v); sub(/:.*/, "", v); gsub(/[ \t]/, "", v)
        if (v != "") print "D\t" cur "\t" v; next
      }
      if (mode == "port" && line ~ /^ *- /) {
        v = line; sub(/^[ \t]*-[ \t]*/, "", v); gsub(/["'\'']/, "", v); gsub(/[ \t]/, "", v)
        if (v != "") print "P\t" cur "\t" v; next
      }
    }
  ')

  declare -A svcid=()
  declare -A svcimg=()
  declare -A svcports=()
  declare -a deps=()
  local tag a b

  # First make sure every service exists, capturing image + ports as metadata.
  while IFS=$'\t' read -r tag a b; do
    case "$tag" in
      S) svcid["$a"]="__pending__" ;;
      I) svcimg["$a"]="$b" ;;
      P) svcports["$a"]+="$b " ;;
      D) deps+=("$a|$b") ;;
    esac
  done <<< "$parsed"

  local svc img cat meta
  for svc in "${!svcid[@]}"; do
    img="${svcimg[$svc]:-service}"
    cat=$(ip_compose_cat "$img")
    meta="image=$img"
    if [ -n "${svcports[$svc]:-}" ]; then
      meta="$meta;ports=${svcports[$svc]};ingress=1"
    fi
    # type field = short image name (without tag) for a friendly listing
    local short="${img%%:*}"; short="${short##*/}"
    [ -z "$short" ] && short="service"
    ip_add_resource "$short" "$svc" "$cat" "$meta"
    svcid["$svc"]="$IP_LAST_ID"
  done

  # Edges from depends_on:  svc -> dependency
  local pair from to
  for pair in "${deps[@]}"; do
    from="${pair%%|*}"; to="${pair##*|}"
    ip_add_edge "${svcid[$from]:-}" "${svcid[$to]:-}"
  done

  return 0
}
