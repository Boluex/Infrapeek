#!/usr/bin/env bash
#
# render_ascii.sh — draw a top-down Unicode box diagram of the resources.
#

# --- guard for standalone use ----------------------------------------------
if ! declare -F ip_repeat >/dev/null 2>&1; then
  ip_repeat(){ local c="$1" n="$2" o="" i; for ((i=0;i<n;i++)); do o+="$c"; done; printf '%s' "$o"; }
fi

# rank used to order the vertical flow (internet at top, datastore at bottom)
ip_rank() {
  case "$1" in
    internet) echo 0 ;; gateway) echo 1 ;; network) echo 2 ;;
    compute)  echo 3 ;; queue)   echo 4 ;; storage) echo 5 ;;
    datastore) echo 6 ;; iam) echo 7 ;; *) echo 8 ;;
  esac
}

# friendly display name for a type, e.g. aws_lambda_function -> "Lambda Function"
ip_pretty_type() {
  local t="$1"
  t="${t#aws_}"; t="${t#google_}"; t="${t#azurerm_}"; t="${t#aws::}"
  t="${t//_/ }"
  # title-case, then upper-case common acronyms
  printf '%s' "$t" | awk '
    { for (i = 1; i <= NF; i++) $i = toupper(substr($i,1,1)) substr($i,2) }
    { print }
  ' | sed -E 's/\b(Api|Db|S3|Iam|Rds|Sqs|Sns|Vpc|Ec2|Eks|Ecs|Acl|Dns|Cdn|Url|Kms|Efs|Ebs)\b/\U\1/g'
}

# string padded/truncated and centred inside width w
ip_center() {
  local s="$1" w="$2" len total l r
  len=${#s}
  if [ "$len" -gt "$w" ]; then s="${s:0:w}"; len="$w"; fi
  total=$((w - len)); l=$((total / 2)); r=$((total - l))
  printf '%s%s%s' "$(ip_repeat ' ' "$l")" "$s" "$(ip_repeat ' ' "$r")"
}

# the ids that belong in the flow diagram, ordered by rank (iam/other excluded)
ip_flow_ids() {
  local id rank
  for id in "${IP_RES_ID[@]}"; do
    case "${IP_RES_CAT[$id]}" in iam|other) continue ;; esac
    printf '%s\t%s\n' "$(ip_rank "${IP_RES_CAT[$id]}")" "$id"
  done | sort -n -s | awk -F'\t' '{print $2}'
}

ip_render_ascii() {
  local LEFT="   "
  local ids=()
  local id
  while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(ip_flow_ids)

  # if everything got filtered out, fall back to every resource
  if [ "${#ids[@]}" -eq 0 ]; then ids=("${IP_RES_ID[@]}"); fi

  # compute the inner width from the widest label/name
  local inner=10 l1 l2
  for id in "${ids[@]}"; do
    l1=$(ip_pretty_type "${IP_RES_TYPE[$id]}")
    l2="${IP_RES_NAME[$id]}"
    [ "${#l1}" -gt "$inner" ] && inner=${#l1}
    [ "${#l2}" -gt "$inner" ] && inner=${#l2}
  done
  [ "$inner" -gt 36 ] && inner=36

  local bt=$((inner + 4))       # total visible box width
  local c=$((bt / 2))           # centre column
  local nd=$((bt - 2))          # number of dashes in a border

  # Internet header if the top of the stack is internet-facing
  local first_cat="${IP_RES_CAT[${ids[0]}]}"
  local show_net=0
  case "$first_cat" in gateway|compute|network) show_net=1 ;; esac

  if [ "$show_net" -eq 1 ]; then
    printf '%s%s\n' "$LEFT" "$(ip_center "Internet" "$bt")"
    printf '%s%s│\n' "$LEFT" "$(ip_repeat ' ' "$c")"
  fi

  local i n="${#ids[@]}"
  for ((i = 0; i < n; i++)); do
    id="${ids[$i]}"
    l1=$(ip_pretty_type "${IP_RES_TYPE[$id]}")
    l2="${IP_RES_NAME[$id]}"

    # top border (with ▼ when this box has something pointing into it)
    local arrow=0
    { [ "$i" -gt 0 ] || [ "$show_net" -eq 1 ]; } && arrow=1
    if [ "$arrow" -eq 1 ]; then
      printf '%s┌%s▼%s┐\n' "$LEFT" "$(ip_repeat '─' "$((c - 1))")" "$(ip_repeat '─' "$((nd - c))")"
    else
      printf '%s┌%s┐\n' "$LEFT" "$(ip_repeat '─' "$nd")"
    fi

    printf '%s│ %s │\n' "$LEFT" "$(ip_center "$l1" "$inner")"
    printf '%s│ %s │\n' "$LEFT" "$(ip_center "$l2" "$inner")"
    printf '%s└%s┘\n' "$LEFT" "$(ip_repeat '─' "$nd")"

    # connector to the next box
    if [ "$i" -lt "$((n - 1))" ]; then
      printf '%s%s│\n' "$LEFT" "$(ip_repeat ' ' "$c")"
    fi
  done
}
