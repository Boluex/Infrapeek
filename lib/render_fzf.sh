#!/usr/bin/env bash
#
# render_fzf.sh — interactive resource browser using fzf.
# Pre-renders a detail file per resource and previews it on selection.
# Degrades gracefully when fzf is not installed.
#

# Build the detail text for a single resource id (used as the fzf preview).
ip_fzf_detail() {
  local id="$1"
  printf 'Type:  %s\n' "${IP_RES_TYPE[$id]}"
  printf 'Name:  %s\n' "${IP_RES_NAME[$id]}"
  printf 'Group: %s\n' "${IP_RES_CAT[$id]}"
  if [ -n "${IP_RES_META[$id]}" ]; then
    printf 'Meta:  %s\n' "${IP_RES_META[$id]}"
  fi
  echo

  echo "Outbound ->"
  local e from to found=0
  for e in "${IP_EDGES[@]}"; do
    from="${e%%|*}"; to="${e##*|}"
    if [ "$from" = "$id" ]; then
      printf '   -> %s %s\n' "${IP_RES_TYPE[$to]}" "${IP_RES_NAME[$to]}"; found=1
    fi
  done
  [ "$found" -eq 0 ] && echo "   (none)"

  echo "Inbound <-"
  found=0
  for e in "${IP_EDGES[@]}"; do
    from="${e%%|*}"; to="${e##*|}"
    if [ "$to" = "$id" ]; then
      printf '   <- %s %s\n' "${IP_RES_TYPE[$from]}" "${IP_RES_NAME[$from]}"; found=1
    fi
  done
  [ "$found" -eq 0 ] && echo "   (none)"
}

ip_render_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    printf '%s‣%s fzf not found — interactive browser unavailable.\n' "${YEL:-}" "${RST:-}"
    printf '    install it:  brew install fzf   |   sudo apt-get install fzf\n'
    return 0
  fi

  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/infrapeek.XXXXXX") || return 1

  local id
  for id in "${IP_RES_ID[@]}"; do
    ip_fzf_detail "$id" > "$tmp/$id"
    printf '%s\t%-26s %s\n' "$id" "${IP_RES_TYPE[$id]}" "${IP_RES_NAME[$id]}" >> "$tmp/list"
  done

  fzf --ansi \
      --delimiter='\t' --with-nth=2.. \
      --prompt='infrapeek> ' \
      --header='↑/↓ to browse resources · ENTER to exit' \
      --preview="cat $tmp/{1}" \
      --preview-window='right:55%:wrap' \
      < "$tmp/list" >/dev/null || true

  rm -rf "$tmp"
}
