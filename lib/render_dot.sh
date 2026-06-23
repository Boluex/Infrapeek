#!/usr/bin/env bash
#
# render_dot.sh — generate a Graphviz .dot file and export PNG + SVG.
# Degrades gracefully when 'dot' is not installed.
#

ip_dot_color() {
  case "$1" in
    gateway)   echo "#4FC3F7" ;;
    compute)   echo "#FFB74D" ;;
    queue)     echo "#BA68C8" ;;
    storage)   echo "#AED581" ;;
    datastore) echo "#E57373" ;;
    network)   echo "#90A4AE" ;;
    iam)       echo "#FFF176" ;;
    *)         echo "#CFD8DC" ;;
  esac
}

# build the .dot source on stdout
ip_build_dot() {
  echo "digraph infrapeek {"
  echo "  rankdir=TB;"
  echo "  bgcolor=\"white\";"
  echo "  node [shape=box style=\"rounded,filled\" fontname=\"Helvetica\" fontsize=11];"
  echo "  edge [color=\"#607D8B\"];"
  local id label color
  for id in "${IP_RES_ID[@]}"; do
    label="${IP_RES_TYPE[$id]}\\n${IP_RES_NAME[$id]}"
    color=$(ip_dot_color "${IP_RES_CAT[$id]}")
    printf '  %s [label="%s" fillcolor="%s"];\n' "$id" "$label" "$color"
  done
  local e from to
  for e in "${IP_EDGES[@]}"; do
    from="${e%%|*}"; to="${e##*|}"
    printf '  %s -> %s;\n' "$from" "$to"
  done
  echo "}"
}

ip_render_dot() {
  local dotfile="infrapeek.dot"
  ip_build_dot > "$dotfile"
  printf '%sDIAGRAM EXPORT%s\n' "${BOLD:-}" "${RST:-}"
  ip_repeat "─" 50; echo
  printf '  wrote %s\n' "$dotfile"

  if command -v dot >/dev/null 2>&1; then
    if dot -Tpng "$dotfile" -o infrapeek-diagram.png 2>/dev/null; then
      printf '  %s✓%s wrote infrapeek-diagram.png\n' "${GRN:-}" "${RST:-}"
    fi
    if dot -Tsvg "$dotfile" -o infrapeek-diagram.svg 2>/dev/null; then
      printf '  %s✓%s wrote infrapeek-diagram.svg\n' "${GRN:-}" "${RST:-}"
    fi
  else
    printf '  %s‣%s graphviz not found — only the .dot file was written.\n' "${YEL:-}" "${RST:-}"
    printf '    install it to render images:\n'
    printf '      macOS:  brew install graphviz\n'
    printf '      Ubuntu: sudo apt-get install graphviz\n'
  fi
}
