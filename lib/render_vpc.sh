#!/usr/bin/env bash
#
# render_vpc.sh — Terraform-aware *nested* AWS network diagram.
#
# Instead of a flat dependency graph, this draws the real containment topology:
#
#   Internet -> IGW -> VPC { public subnet { instances }, private subnets {...} }
#
# plus a DATA FLOW section derived from security-group ingress rules. Uses plain
# ASCII box characters (+ - |) so widths are exact and it copies/pastes cleanly.
#
# Relies on IP_RAW (concatenated *.tf) and IP_DIR (project dir for var lookups).

# ---- small ASCII box-composition helpers -----------------------------------
_vrep() { local i o=""; for ((i = 0; i < $2; i++)); do o+="$1"; done; printf '%s' "$o"; }

# wrap stdin lines in an ASCII border
_vbox() {
  local -a L=(); local l w=0
  while IFS= read -r l; do L+=("$l"); ((${#l} > w)) && w=${#l}; done
  printf '+%s+\n' "$(_vrep - $((w + 2)))"
  for l in "${L[@]}"; do printf '| %-*s |\n' "$w" "$l"; done
  printf '+%s+\n' "$(_vrep - $((w + 2)))"
}

# place several blocks (newline-joined strings) side by side, top-aligned
_vhbox() {
  local gap="  "
  local -a B=("$@"); local n=${#B[@]} i r maxh=0
  local -a WW=(); declare -A C=()
  for ((i = 0; i < n; i++)); do
    local -a ls=(); mapfile -t ls <<< "${B[i]}"
    ((${#ls[@]} > maxh)) && maxh=${#ls[@]}
    local w=0
    for r in "${!ls[@]}"; do C[$i,$r]="${ls[r]}"; ((${#ls[r]} > w)) && w=${#ls[r]}; done
    WW[i]=$w
  done
  for ((r = 0; r < maxh; r++)); do
    local out=""
    for ((i = 0; i < n; i++)); do
      [ "$i" -gt 0 ] && out+="$gap"
      local seg; printf -v seg '%-*s' "${WW[i]}" "${C[$i,$r]:-}"
      out+="$seg"
    done
    out="${out%"${out##*[![:space:]]}"}"   # rstrip
    printf '%s\n' "$out"
  done
}

# paint a single row of width $1, placing "col=text" items (';'-separated) in $2
_row() {
  local w="$1" spec="$2"
  local -a g; local i; for ((i = 0; i < w; i++)); do g[i]=' '; done
  local item col txt k oldIFS="$IFS"; IFS=';'
  for item in $spec; do
    [ -z "$item" ] && continue
    col="${item%%=*}"; txt="${item#*=}"
    for ((k = 0; k < ${#txt}; k++)); do
      [ $((col + k)) -ge 0 ] && [ $((col + k)) -lt "$w" ] && g[$((col + k))]="${txt:$k:1}"
    done
  done
  IFS="$oldIFS"; printf '%s' "${g[@]}"; printf '\n'
}

# friendly label for an inbound-from-Internet flow, given its port list
_inb_label() {
  local ports=" $1 "
  case "$ports" in
    *" 80 "*|*" 443 "*)
      local web="" p
      for p in $1; do { [ "$p" = "80" ] || [ "$p" = "443" ]; } && web+="$p/"; done
      echo "Public Web Traffic (${web%/})" ;;
    *" 22 "*) echo "SSH Administration (Port 22)" ;;
    *) local f="" p; for p in $1; do f+="$p,"; done; echo "Inbound (${f%,})" ;;
  esac
}

# ---- variable resolution (var.x -> default / tfvars value) ------------------
ip_build_varmap() {
  local dir="$1"
  declare -gA IP_VAR=()
  local parsed k v
  parsed=$(cat "$dir"/*.tf 2>/dev/null | awk '
    /^variable[ \t]+"/ { if (match($0, /"[^"]+"/)) vn = substr($0, RSTART + 1, RLENGTH - 2); invar = 1 }
    invar && /default[ \t]*=/ {
      v = $0; sub(/.*default[ \t]*=[ \t]*/, "", v); gsub(/"/, "", v); sub(/[ \t].*/, "", v)
      if (vn != "") { print vn "\t" v; vn = "" }
    }
    /^}/ { invar = 0 }
  ')
  while IFS=$'\t' read -r k v; do [ -n "$k" ] && IP_VAR["$k"]="$v"; done <<< "$parsed"

  if [ -f "$dir/terraform.tfvars" ]; then
    parsed=$(awk -F'=' '
      /^[ \t]*[A-Za-z0-9_]+[ \t]*=/ {
        k = $1; v = $2; gsub(/[ \t]/, "", k); gsub(/"/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
        print k "\t" v
      }' "$dir/terraform.tfvars")
    while IFS=$'\t' read -r k v; do [ -n "$k" ] && IP_VAR["$k"]="$v"; done <<< "$parsed"
  fi
}
ip_resolve() {
  case "$1" in
    var.*) printf '%s' "${IP_VAR[${1#var.}]:-$1}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# friendly instance label from its Role tag
ip_role_label() {
  case "$1" in
    bastion)            echo "Bastion Host" ;;
    nginx)              echo "Nginx Frontend" ;;
    django)             echo "Django Backend" ;;
    postgresql|postgres) echo "Postgres Database" ;;
    "")                 echo "EC2 Instance" ;;
    *)                  echo "$1" ;;
  esac
}
ip_port_name() {
  case "$1" in
    22)   echo "22/SSH" ;;
    80)   echo "80/HTTP" ;;
    443)  echo "443/HTTPS" ;;
    8000) echo "8000/app" ;;
    5432) echo "5432/PostgreSQL" ;;
    3306) echo "3306/MySQL" ;;
    *)    echo "$1" ;;
  esac
}

# Parse the AWS network topology + security-group flows from IP_RAW into a set
# of GLOBAL arrays, shared by both the ASCII renderer and the Graphviz builder.
ip_parse_vpc_topology() {
  local IP_DIR="${IP_DIR:-.}"

  declare -gA SUB_CIDR=() SUB_PUB=() INST_SNET=() INST_ROLE=() INST_SG=() SG2INST=()
  declare -ga SUBS=() INSTS=() F_SRC=() F_PORT=() F_DST=()
  VPC_NAME=""; VPC_CIDR=""; IGW_NAME=""; NAT_NAME=""; NAT_SUBNET=""

  local topo
  topo=$(printf '%s\n' "$IP_RAW" | awk '
    function flush() {
      if (ct == "aws_vpc")                   print "vpc\t" cn "\t" cidr
      else if (ct == "aws_subnet")           print "subnet\t" cn "\t" cidr "\t" pub
      else if (ct == "aws_instance")         print "instance\t" cn "\t" snet "\t" rol "\t" sgrp
      else if (ct == "aws_nat_gateway")      print "nat\t" cn "\t" snet
      else if (ct == "aws_internet_gateway") print "igw\t" cn
      ct = ""; cn = ""; cidr = ""; pub = 0; snet = ""; rol = ""; sgrp = ""
    }
    {
      line = $0
      if (depth == 0 && line ~ /^[ \t]*resource[ \t]+"/) {
        if (match(line, /"[^"]+"[ \t]+"[^"]+"/)) {
          seg = substr(line, RSTART, RLENGTH); gsub(/"/, "", seg); split(seg, a, /[ \t]+/); ct = a[1]; cn = a[2]
        }
      }
      if (ct != "") {
        if (line ~ /cidr_block[ \t]*=/ && cidr == "") { v = line; sub(/.*cidr_block[ \t]*=[ \t]*/, "", v); gsub(/"/, "", v); sub(/[ \t].*/, "", v); cidr = v }
        if (line ~ /map_public_ip_on_launch[ \t]*=[ \t]*true/) pub = 1
        if (line ~ /subnet_id[ \t]*=/ && snet == "") { if (match(line, /aws_subnet\.[A-Za-z0-9_]+/)) { s = substr(line, RSTART, RLENGTH); sub(/aws_subnet\./, "", s); snet = s } }
        if (line ~ /Role[ \t]*=/ && rol == "") { v = line; sub(/.*Role[ \t]*=[ \t]*/, "", v); gsub(/"/, "", v); sub(/[ \t].*/, "", v); rol = v }
        if (line ~ /vpc_security_group_ids/ && sgrp == "") { if (match(line, /aws_security_group\.[A-Za-z0-9_]+/)) { s = substr(line, RSTART, RLENGTH); sub(/aws_security_group\./, "", s); sgrp = s } }
      }
      o = gsub(/{/, "{", line); c = gsub(/}/, "}", line)
      depth += o - c
      if (depth <= 0 && ct != "") { depth = 0; flush() }
    }
  ')

  ip_build_varmap "$IP_DIR"

  local tag a b c d
  while IFS=$'\t' read -r tag a b c d; do
    case "$tag" in
      vpc)      VPC_NAME="$a"; VPC_CIDR=$(ip_resolve "$b") ;;
      subnet)   SUBS+=("$a"); SUB_CIDR["$a"]=$(ip_resolve "$b"); SUB_PUB["$a"]="$c" ;;
      instance) INSTS+=("$a"); INST_SNET["$a"]="$b"; INST_ROLE["$a"]="$c"; INST_SG["$a"]="$d" ;;
      nat)      NAT_NAME="$a"; NAT_SUBNET="$b" ;;
      igw)      IGW_NAME="$a" ;;
    esac
  done <<< "$topo"

  [ -z "$VPC_NAME" ] && return 1

  # ---- parse security-group ingress rules into flow arrays ----
  local flow
  flow=$(printf '%s\n' "$IP_RAW" | awk '
    {
      line = $0
      if (d == 0 && line ~ /^[ \t]*resource[ \t]+"aws_security_group"/) {
        if (match(line, /"aws_security_group"[ \t]+"[^"]+"/)) { seg = substr(line, RSTART, RLENGTH); gsub(/"/, "", seg); split(seg, a, /[ \t]+/); sgn = a[2] }
        insg = 1
      }
      if (insg) {
        if (line ~ /ingress[ \t]*{/) { ing = 1; port = ""; src = ""; ingd = d + 1 }
        if (ing) {
          if (line ~ /from_port[ \t]*=/) { v = line; gsub(/[^0-9]/, "", v); if (v != "") port = v }
          if (line ~ /0\.0\.0\.0\/0/ && src == "") src = "Internet"
          if (line ~ /security_groups/ && src == "") { if (match(line, /aws_security_group\.[A-Za-z0-9_]+/)) { s = substr(line, RSTART, RLENGTH); sub(/aws_security_group\./, "", s); src = s } }
        }
      }
      o = gsub(/{/, "{", line); c = gsub(/}/, "}", line)
      d += o - c
      if (ing && d < ingd) { if (port != "") print "flow\t" sgn "\t" port "\t" src; ing = 0 }
      if (insg && d <= 0) { d = 0; insg = 0; sgn = "" }
    }
  ')

  local id
  for id in "${INSTS[@]}"; do [ -n "${INST_SG[$id]}" ] && SG2INST["${INST_SG[$id]}"]="$id"; done

  local tg sgn port src dstid srcid
  while IFS=$'\t' read -r tg sgn port src; do
    [ "$tg" = "flow" ] || continue
    dstid="${SG2INST[$sgn]:-}"; [ -z "$dstid" ] && continue
    if [ "$src" = "Internet" ]; then srcid="Internet"; else srcid="${SG2INST[$src]:-$src}"; fi
    F_SRC+=("$srcid"); F_PORT+=("$port"); F_DST+=("$dstid")
  done <<< "$flow"
  return 0
}

ip_render_vpc() {
  if ! ip_parse_vpc_topology; then ip_render_tree; return; fi

  # friendly label for an endpoint (instance id or "Internet")
  _lab() { [ "$1" = "Internet" ] && { echo "Internet"; return; }; ip_role_label "${INST_ROLE[$1]:-}"; }

  # ---- box for one instance ----
  _inst_box() {
    printf '%s\n(%s)\n' "$(ip_role_label "${INST_ROLE[$1]}")" "$1" | _vbox
  }

  # ---- block for one subnet (title + its instance boxes side by side) ----
  _subnet_block() {
    local sn="$1" title="$2"
    local -a boxes=(); local id
    for id in "${INSTS[@]}"; do [ "${INST_SNET[$id]}" = "$sn" ] && boxes+=("$(_inst_box "$id")"); done
    [ "$NAT_SUBNET" = "$sn" ] && boxes+=("$(printf 'NAT Gateway\n(%s)\n' "$NAT_NAME" | _vbox)")
    local inner
    if [ "${#boxes[@]}" -gt 0 ]; then inner=$(_vhbox "${boxes[@]}"); else inner="(no compute)"; fi
    { printf '%s\n\n' "$title"; printf '%s\n' "$inner"; } | _vbox
  }

  # ---- arrow gap printed above a subnet: ingress (v) into it + egress (^) out ----
  _gap_for() {
    local sub="$1" i out=""
    for i in "${!F_DST[@]}"; do
      local dst="${F_DST[$i]}" srce="${F_SRC[$i]}"
      [ "${INST_SNET[$dst]:-}" = "$sub" ] || continue
      # skip traffic that originates inside the same subnet (not a crossing)
      [ "$srce" != "Internet" ] && [ "${INST_SNET[$srce]:-}" = "$sub" ] && continue
      out+="$(printf '      |  v  %-15s %s --> %s' "$(ip_port_name "${F_PORT[$i]}")" "$(_lab "$srce")" "$(_lab "$dst")")"$'\n'
    done
    if [ "${SUB_PUB[$sub]}" != "1" ]; then
      for id in "${INSTS[@]}"; do
        [ "${INST_SNET[$id]}" = "$sub" ] || continue
        out+="$(printf '      |  ^  %-15s %s --> NAT Gateway --> Internet' "egress" "$(_lab "$id")")"$'\n'
      done
    fi
    printf '%s' "$out"
  }

  # ---- assemble the VPC interior: public subnet(s) first, then private ----
  local vpc_inner="" sn title gap pidx=1
  for sn in "${SUBS[@]}"; do
    [ "${SUB_PUB[$sn]}" = "1" ] || continue
    title="PUBLIC SUBNET (${SUB_CIDR[$sn]})  -  routes to Internet via IGW"
    vpc_inner+="$(_subnet_block "$sn" "$title")"$'\n'
  done
  for sn in "${SUBS[@]}"; do
    [ "${SUB_PUB[$sn]}" = "1" ] && continue
    gap="$(_gap_for "$sn")"
    vpc_inner+=$'\n'
    [ -n "$gap" ] && vpc_inner+="${gap}"$'\n'
    title="PRIVATE SUBNET ${pidx} (${SUB_CIDR[$sn]})  -  outbound via NAT Gateway"
    vpc_inner+="$(_subnet_block "$sn" "$title")"$'\n'
    pidx=$((pidx + 1))
  done
  vpc_inner="${vpc_inner%$'\n'}"

  local vpc_block
  vpc_block=$( { printf 'VIRTUAL PRIVATE CLOUD (VPC)   %s\n\n' "$VPC_CIDR"; printf '%s\n' "$vpc_inner"; } | _vbox )

  # ---- render: PUBLIC INTERNET -> labelled inbound fan -> VPC ----
  local total_w; total_w=$(printf '%s\n' "$vpc_block" | awk '{ if (length > m) m = length } END { print m }')
  local W=$total_w

  # group inbound-from-Internet flows by destination instance
  local -A INP=(); local -a ORD=(); local k
  for k in "${!F_DST[@]}"; do
    [ "${F_SRC[$k]}" = "Internet" ] || continue
    local dd="${F_DST[$k]}"
    [ -z "${INP[$dd]:-}" ] && ORD+=("$dd")
    INP[$dd]+="${F_PORT[$k]} "
  done
  local N=${#ORD[@]}

  if [ "$N" -gt 0 ]; then
    local margin=7; local -a COL=(); local j
    if [ "$N" -eq 1 ]; then
      COL=( $((W / 2)) )
    else
      local span=$((W - 1 - 2 * margin))
      for ((j = 0; j < N; j++)); do COL+=( $(( margin + j * span / (N - 1) )) ); done
    fi

    local ind=$(( (W - 22) / 2 )); [ "$ind" -lt 0 ] && ind=0
    local pad; pad=$(_vrep ' ' "$ind")
    printf '%s+--------------------+\n' "$pad"
    printf '%s|   PUBLIC INTERNET  |\n' "$pad"
    printf '%s+---------+----------+\n' "$pad"

    local cx=$((ind + 10))                       # internet box centre column
    _row "$W" "$cx=|"

    local lo=${COL[0]} hi=${COL[$((N - 1))]}
    local busspec="$lo=$(_vrep - $((hi - lo + 1)))"
    for j in "${COL[@]}"; do busspec+=";$j=+"; done
    busspec+=";$cx=+"
    _row "$W" "$busspec"

    local lblspec="" jj c lbl start
    for jj in "${!COL[@]}"; do
      c=${COL[$jj]}; lbl=$(_inb_label "${INP[${ORD[$jj]}]}")
      if [ "$c" -le $((W / 2)) ]; then start=$((c + 2)); else start=$(( c - ${#lbl} - 1 )); fi
      [ "$start" -lt 0 ] && start=0
      lblspec+=";$c=|;$start=$lbl"
    done
    _row "$W" "$lblspec"

    local arrspec=""; for j in "${COL[@]}"; do arrspec+=";$j=v"; done
    _row "$W" "$arrspec"

    # tick the VPC top border where the arrows land
    local -a VL; mapfile -t VL <<< "$vpc_block"
    local line0="${VL[0]}"
    for j in "${COL[@]}"; do line0="${line0:0:j}+${line0:$((j + 1))}"; done
    VL[0]="$line0"
    printf '%s\n' "${VL[@]}"
  else
    printf '%s\n' "$vpc_block"
  fi
  printf '\n  Legend:  v = inbound into a subnet/VPC      ^ = egress out via NAT\n'

  # ---- DATA FLOW summary (same rules, listed) ----
  echo
  printf '%sDATA FLOW%s  (from security group ingress rules)\n' "${BOLD:-}" "${RST:-}"
  ip_repeat - 50; echo
  local i
  for i in "${!F_DST[@]}"; do
    printf '  %-18s --%-15s-->  %s\n' "$(_lab "${F_SRC[$i]}")" " $(ip_port_name "${F_PORT[$i]}")" "$(_lab "${F_DST[$i]}")"
  done
}

# ---------------------------------------------------------------------------
# Graphviz: emit the *nested* VPC view as clustered DOT (matches the ASCII one)
# ---------------------------------------------------------------------------
ip_build_vpc_dot() {
  ip_parse_vpc_topology || return 1

  _emit_subnet() {   # $1=subnet name  $2=title  $3=bgcolor
    local sn="$1" title="$2" bg="$3" i rl col
    echo "    subgraph cluster_${sn} {"
    echo "      label=\"${title}\"; style=\"rounded,filled\"; color=\"#90A4AE\"; fillcolor=\"${bg}\"; fontname=\"Helvetica-Bold\";"
    for i in "${INSTS[@]}"; do
      [ "${INST_SNET[$i]}" = "$sn" ] || continue
      rl="${INST_ROLE[$i]}"; col="#FFB74D"
      case "$rl" in
        postgresql|postgres) col="#E57373" ;;
        nginx)               col="#81C784" ;;
        bastion)             col="#FFD54F" ;;
      esac
      echo "      n_${i} [label=\"$(ip_role_label "$rl")\\n(${i})\" shape=box style=\"rounded,filled\" fillcolor=\"${col}\"];"
    done
    [ "$NAT_SUBNET" = "$sn" ] && \
      echo "      nat [label=\"NAT Gateway\\n(${NAT_NAME})\" shape=box style=\"rounded,filled\" fillcolor=\"#B0BEC5\"];"
    echo "    }"
  }

  echo "digraph infrapeek {"
  echo "  rankdir=TB; compound=true; labelloc=t;"
  echo "  graph [fontname=\"Helvetica\"]; node [fontname=\"Helvetica\" fontsize=10]; edge [fontsize=9 color=\"#546E7A\"];"
  echo "  Internet [label=\"Public Internet\" shape=ellipse style=filled fillcolor=\"#ECEFF1\"];"
  echo "  subgraph cluster_vpc {"
  echo "    label=\"VIRTUAL PRIVATE CLOUD (VPC)   ${VPC_CIDR}\"; style=rounded; color=\"#37474F\"; fontname=\"Helvetica-Bold\";"

  local sn idx=1
  for sn in "${SUBS[@]}"; do [ "${SUB_PUB[$sn]}" = "1" ] || continue
    _emit_subnet "$sn" "PUBLIC SUBNET (${SUB_CIDR[$sn]})" "#E3F2FD"
  done
  for sn in "${SUBS[@]}"; do [ "${SUB_PUB[$sn]}" = "1" ] && continue
    _emit_subnet "$sn" "PRIVATE SUBNET ${idx} (${SUB_CIDR[$sn]})" "#FFF3E0"
    idx=$((idx + 1))
  done
  echo "  }"

  # ingress / app-tier flow edges (from security groups)
  local i src
  for i in "${!F_DST[@]}"; do
    src="${F_SRC[$i]}"; [ "$src" = "Internet" ] && src="Internet" || src="n_${src}"
    echo "  ${src} -> n_${F_DST[$i]} [label=\"$(ip_port_name "${F_PORT[$i]}")\"];"
  done
  # egress: private instances -> NAT -> Internet
  if [ -n "$NAT_NAME" ]; then
    for i in "${INSTS[@]}"; do
      [ "${SUB_PUB[${INST_SNET[$i]}]}" = "1" ] && continue
      echo "  n_${i} -> nat [label=\"egress\" style=dashed color=\"#90A4AE\"];"
    done
    echo "  nat -> Internet [label=\"outbound\" style=dashed color=\"#90A4AE\"];"
  fi
  echo "}"
}

# Export the nested VPC view to PNG + SVG (used by --diagram for TF VPC projects).
ip_render_vpc_diagram() {
  local dotfile="infrapeek.dot"
  ip_build_vpc_dot > "$dotfile" || { ip_render_dot; return; }
  printf '%sDIAGRAM EXPORT%s  (nested VPC view)\n' "${BOLD:-}" "${RST:-}"
  ip_repeat "─" 50; echo
  printf '  wrote %s\n' "$dotfile"
  if command -v dot >/dev/null 2>&1; then
    dot -Tpng "$dotfile" -o infrapeek-diagram.png 2>/dev/null && \
      printf '  %s✓%s wrote infrapeek-diagram.png\n' "${GRN:-}" "${RST:-}"
    dot -Tsvg "$dotfile" -o infrapeek-diagram.svg 2>/dev/null && \
      printf '  %s✓%s wrote infrapeek-diagram.svg\n' "${GRN:-}" "${RST:-}"
  else
    printf '  %s‣%s graphviz not found — install it to render images:\n' "${YEL:-}" "${RST:-}"
    printf '      macOS: brew install graphviz   |   Ubuntu: sudo apt-get install graphviz\n'
  fi
}
