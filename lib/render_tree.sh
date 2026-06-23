#!/usr/bin/env bash
#
# render_tree.sh — clean, layered branching ASCII diagram.
#
# Unlike render_ascii.sh (a single vertical stack) this groups resources into
# layers by category and draws fan-out / fan-in connectors between layers, e.g.
#
#                Internet
#                   │
#          ┌────────▼────────┐
#          │  Load Balancer  │
#          └────────┬────────┘
#          ┌────────┴────────┐
#          │                 │
#   ┌──────▼──────┐   ┌──────▼──────┐
#   │ Backend Pod │   │ Backend Pod │
#   └──────┬──────┘   └──────┬──────┘
#          └────────┬────────┘
#                ┌──▼──┐
#                │ DB  │
#                └─────┘
#
# Reuses helpers from render_ascii.sh (ip_repeat, ip_center, ip_pretty_type,
# ip_rank, ip_flow_ids) — source this after render_ascii.sh.

# Section title for a category layer (used by the compact grouped view).
ip_layer_title() {
  case "$1" in
    gateway)   echo "Entry / Gateway" ;;
    network)   echo "Network" ;;
    compute)   echo "Compute" ;;
    queue)     echo "Messaging" ;;
    storage)   echo "Storage" ;;
    datastore) echo "Data Store" ;;
    iam)       echo "Security" ;;
    *)         echo "Other" ;;
  esac
}

# Compact, always-narrow view that still shows branching: category layers are
# stacked top-to-bottom (the flow), and the parallel resources within each layer
# are listed as sibling branches. Fits any terminal width.
ip_render_layers_compact() {
  local ids; ids=$(ip_flow_ids)
  [ -z "$ids" ] && ids="${IP_RES_ID[*]}"

  local -a L_IDS=(); local prev="" id r
  for id in $ids; do
    r=$(ip_rank "${IP_RES_CAT[$id]}")
    if [ "$r" != "$prev" ]; then L_IDS+=("$id"); prev="$r"
    else local k=$(( ${#L_IDS[@]} - 1 )); L_IDS[$k]="${L_IDS[$k]} $id"; fi
  done

  # width of the type column
  local twidth=4 a
  for id in $ids; do
    a=$(ip_pretty_type "${IP_RES_TYPE[$id]}")
    [ "${#a}" -gt "$twidth" ] && twidth=${#a}
  done

  local first=(${L_IDS[0]}) fc
  fc="${IP_RES_CAT[${first[0]}]}"
  case "$fc" in gateway|compute|network) printf '   Internet\n      │\n' ;; esac

  local li nlayers=${#L_IDS[@]}
  for li in "${!L_IDS[@]}"; do
    local arr=(${L_IDS[$li]})
    printf '   %s%s%s\n' "${BOLD:-}" "$(ip_layer_title "${IP_RES_CAT[${arr[0]}]}")" "${RST:-}"
    local i n=${#arr[@]} b
    for ((i = 0; i < n; i++)); do
      b="├─"; [ "$i" -eq $((n - 1)) ] && b="└─"
      id="${arr[$i]}"
      printf '   %s %-*s  %s%s%s\n' "$b" "$twidth" "$(ip_pretty_type "${IP_RES_TYPE[$id]}")" \
        "${DIM:-}" "${IP_RES_NAME[$id]}" "${RST:-}"
    done
    [ "$li" -lt $((nlayers - 1)) ] && printf '   │\n'
  done
}

_tree_min() { local m="$1"; shift; local x; for x in "$@"; do [ "$x" -lt "$m" ] && m="$x"; done; printf '%s' "$m"; }
_tree_max() { local m="$1"; shift; local x; for x in "$@"; do [ "$x" -gt "$m" ] && m="$x"; done; printf '%s' "$m"; }

# Emit one row of width $1, placing glyphs from "col:glyph;col:glyph;..." ($2).
_tree_row() {
  local width="$1" spec="$2"
  local -a cells; local i
  for ((i = 0; i < width; i++)); do cells[i]=' '; done
  local item col g oldIFS="$IFS"
  IFS=';'
  for item in $spec; do
    [ -z "$item" ] && continue
    col="${item%%:*}"; g="${item#*:}"
    [ "$col" -ge 0 ] && [ "$col" -lt "$width" ] && cells[col]="$g"
  done
  IFS="$oldIFS"
  printf '%s' "${cells[@]}"; printf '\n'
}

# Draw the connector block between a set of source centres and target centres.
_tree_connector() {
  local maxw="$1" sources="$2" targets="$3"
  local -a sarr=($sources) tarr=($targets)

  # straight 1:1 in the same column -> a single pipe
  if [ "${#sarr[@]}" -eq 1 ] && [ "${#tarr[@]}" -eq 1 ] && [ "${sarr[0]}" = "${tarr[0]}" ]; then
    _tree_row "$maxw" "${sarr[0]}:│"
    return
  fi

  local c spec=""

  # row 1: a pipe dropping out of each source box
  for c in $sources; do spec+="$c:│;"; done
  _tree_row "$maxw" "$spec"

  # row 2: the horizontal "bus" with corners/tees
  local lo hi
  lo=$(_tree_min $sources $targets); hi=$(_tree_max $sources $targets)
  declare -A isS=() isT=()
  for c in $sources; do isS[$c]=1; done
  for c in $targets; do isT[$c]=1; done
  spec=""
  local col up dn g
  for ((col = lo; col <= hi; col++)); do
    up="${isS[$col]:-}"; dn="${isT[$col]:-}"; g='─'
    if [ -n "$up" ] && [ -n "$dn" ]; then
      g='┼'
    elif [ -n "$up" ]; then
      if [ "$col" -eq "$lo" ]; then g='└'; elif [ "$col" -eq "$hi" ]; then g='┘'; else g='┴'; fi
    elif [ -n "$dn" ]; then
      if [ "$col" -eq "$lo" ]; then g='┌'; elif [ "$col" -eq "$hi" ]; then g='┐'; else g='┬'; fi
    fi
    spec+="$col:$g;"
  done
  _tree_row "$maxw" "$spec"

  # row 3: a pipe dropping into each target box (the box top adds the ▼)
  spec=""
  for c in $targets; do spec+="$c:│;"; done
  _tree_row "$maxw" "$spec"
}

# Render one layer of boxes (4 rows: top, label1, label2, bottom).
_tree_layer_boxes() {
  local maxw="$1"; local -a ids=($2); local -a cen=($3)
  local top="$4" bot="$5" inner="$6" Wb="$7" gap="$8"
  local cpos=$((Wb / 2)); local ndash=$((inner + 2))
  local leftpad=$(( ${cen[0]} - cpos )); [ "$leftpad" -lt 0 ] && leftpad=0
  local pads gaps; pads=$(ip_repeat ' ' "$leftpad"); gaps=$(ip_repeat ' ' "$gap")

  local rtop="$pads" rl1="$pads" rl2="$pads" rbot="$pads"
  local i id p1 p2
  for ((i = 0; i < ${#ids[@]}; i++)); do
    if [ "$i" -gt 0 ]; then rtop+="$gaps"; rl1+="$gaps"; rl2+="$gaps"; rbot+="$gaps"; fi
    id="${ids[$i]}"
    p1=$(ip_pretty_type "${IP_RES_TYPE[$id]}")
    p2="${IP_RES_NAME[$id]}"
    if [ "$top" -eq 1 ]; then
      rtop+="┌$(ip_repeat '─' $((cpos - 1)))▼$(ip_repeat '─' $((ndash - cpos)))┐"
    else
      rtop+="┌$(ip_repeat '─' "$ndash")┐"
    fi
    rl1+="│ $(ip_center "$p1" "$inner") │"
    rl2+="│ $(ip_center "$p2" "$inner") │"
    if [ "$bot" -eq 1 ]; then
      rbot+="└$(ip_repeat '─' $((cpos - 1)))┬$(ip_repeat '─' $((ndash - cpos)))┘"
    else
      rbot+="└$(ip_repeat '─' "$ndash")┘"
    fi
  done
  printf '%s\n%s\n%s\n%s\n' "$rtop" "$rl1" "$rl2" "$rbot"
}

ip_render_tree() {
  local GAP=4

  # group flow ids into layers by category rank
  local ids; ids=$(ip_flow_ids)
  [ -z "$ids" ] && ids="${IP_RES_ID[*]}"
  local -a L_IDS=()
  local prevrank="" id r
  for id in $ids; do
    r=$(ip_rank "${IP_RES_CAT[$id]}")
    if [ "$r" != "$prevrank" ]; then
      L_IDS+=("$id"); prevrank="$r"
    else
      local k=$(( ${#L_IDS[@]} - 1 )); L_IDS[$k]="${L_IDS[$k]} $id"
    fi
  done
  local nlayers=${#L_IDS[@]}
  [ "$nlayers" -eq 0 ] && return 0

  # box inner width from the widest label (capped so it stays readable)
  local inner=10 a b
  for id in $ids; do
    a=$(ip_pretty_type "${IP_RES_TYPE[$id]}"); b="${IP_RES_NAME[$id]}"
    [ "${#a}" -gt "$inner" ] && inner=${#a}
    [ "${#b}" -gt "$inner" ] && inner=${#b}
  done
  [ "$inner" -gt 21 ] && inner=21
  local Wb=$((inner + 4)) cpos
  cpos=$((Wb / 2))

  # layer spans + overall width
  local maxw=$Wb li
  local -a SPAN=()
  for li in "${!L_IDS[@]}"; do
    local arr=(${L_IDS[$li]}); local n=${#arr[@]}
    local span=$(( n * Wb + (n - 1) * GAP ))
    SPAN[$li]=$span
    [ "$span" -gt "$maxw" ] && maxw=$span
  done

  # If the branching tree is wider than the terminal, fall back to the compact
  # vertical layout (always narrow) so it never looks squeezed. IP_TERM_WIDTH=0
  # means "no limit" (piped output or --wide).
  local fit="${IP_TERM_WIDTH:-0}"
  if [ "$fit" -gt 0 ] && [ "$maxw" -gt "$fit" ]; then
    ip_render_layers_compact
    printf '\n  %s‣%s wide branching view is %s cols — too big for your %s-col terminal,\n' \
      "${YEL:-}" "${RST:-}" "$maxw" "$fit"
    printf '     so it is grouped by layer above. For the side-by-side branches:\n'
    printf '       infrapeek --diagram          (PNG/SVG image)\n'
    printf '       infrapeek --wide | less -S   (scroll sideways in terminal)\n'
    return 0
  fi

  # centre column of every box, per layer
  local -a CEN=()
  for li in "${!L_IDS[@]}"; do
    local arr=(${L_IDS[$li]}); local n=${#arr[@]}
    local leftpad=$(( (maxw - SPAN[li]) / 2 )) cs="" i
    for ((i = 0; i < n; i++)); do
      cs+="$(( leftpad + i * (Wb + GAP) + cpos )) "
    done
    CEN[$li]="$cs"
  done

  # optional Internet entry point
  local first_arr=(${L_IDS[0]}) fc show_net=0
  fc="${IP_RES_CAT[${first_arr[0]}]}"
  case "$fc" in gateway|compute|network) show_net=1 ;; esac
  if [ "$show_net" -eq 1 ]; then
    # align the Internet trunk with the first layer: a single box -> straight
    # line; multiple boxes -> drop into the middle and fan out.
    local -a c0=(${CEN[0]}) netcol
    if [ "${#c0[@]}" -eq 1 ]; then netcol="${c0[0]}"; else netcol=$((maxw / 2)); fi
    printf '%s\n' "$(ip_center "Internet" "$maxw")"
    _tree_connector "$maxw" "$netcol" "${CEN[0]}"
  fi

  # draw each layer + the connector to the next
  for li in "${!L_IDS[@]}"; do
    local top=0 bot=0
    { [ "$li" -gt 0 ] || [ "$show_net" -eq 1 ]; } && top=1
    [ "$li" -lt $((nlayers - 1)) ] && bot=1
    _tree_layer_boxes "$maxw" "${L_IDS[$li]}" "${CEN[$li]}" "$top" "$bot" "$inner" "$Wb" "$GAP"
    if [ "$li" -lt $((nlayers - 1)) ]; then
      _tree_connector "$maxw" "${CEN[$li]}" "${CEN[$((li + 1))]}"
    fi
  done
}
