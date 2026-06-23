#!/usr/bin/env bash
#
# render_mermaid.sh — terminal-viewable diagrams of the *real* dependency graph
# (uses the parsed edges, unlike the simplified top-down ASCII flow).
#
#   ip_render_mermaid     -> prints a Mermaid `graph TD` block + writes .mmd
#   ip_render_graph_ascii -> prints the real graph as ASCII box-art (graph-easy)
#

# Mermaid classDef colour per category (matches the PNG/SVG palette).
_ip_mermaid_classdefs() {
  echo "  classDef gateway fill:#4FC3F7,stroke:#0277BD,color:#000;"
  echo "  classDef compute fill:#FFB74D,stroke:#E65100,color:#000;"
  echo "  classDef queue fill:#BA68C8,stroke:#6A1B9A,color:#fff;"
  echo "  classDef storage fill:#AED581,stroke:#558B2F,color:#000;"
  echo "  classDef datastore fill:#E57373,stroke:#C62828,color:#000;"
  echo "  classDef network fill:#90A4AE,stroke:#37474F,color:#000;"
  echo "  classDef iam fill:#FFF176,stroke:#F9A825,color:#000;"
  echo "  classDef other fill:#CFD8DC,stroke:#546E7A,color:#000;"
}

# Build a Mermaid graph definition on stdout.
ip_build_mermaid() {
  echo "graph TD"
  local id label
  for id in "${IP_RES_ID[@]}"; do
    # Mermaid label: <type> on line 1, <name> on line 2. <br/> = newline.
    label="${IP_RES_TYPE[$id]}<br/>${IP_RES_NAME[$id]}"
    printf '  %s["%s"]\n' "$id" "$label"
  done

  local e from to
  for e in "${IP_EDGES[@]}"; do
    from="${e%%|*}"; to="${e##*|}"
    printf '  %s --> %s\n' "$from" "$to"
  done

  _ip_mermaid_classdefs
  for id in "${IP_RES_ID[@]}"; do
    printf '  class %s %s;\n' "$id" "${IP_RES_CAT[$id]}"
  done
}

ip_render_mermaid() {
  local mmd="infrapeek.mmd"
  printf '%sMERMAID DIAGRAM%s  (real dependency graph)\n' "${BOLD:-}" "${RST:-}"
  ip_repeat "─" 50; echo
  echo '```mermaid'
  ip_build_mermaid | tee "$mmd"
  echo '```'
  echo
  printf '  %s‣%s wrote %s\n' "${CYN:-}" "${RST:-}" "$mmd"
  printf '  %s‣%s paste the block above into https://mermaid.live, a GitHub\n' "${CYN:-}" "${RST:-}"
  printf '     markdown file, or the VS Code "Markdown Preview Mermaid" extension.\n'
}

# Render the real graph as ASCII box-art in the terminal, via graph-easy.
ip_render_graph_ascii() {
  printf '%sGRAPH (ASCII)%s  (real dependency graph)\n' "${BOLD:-}" "${RST:-}"
  ip_repeat "─" 50; echo

  if ! command -v graph-easy >/dev/null 2>&1; then
    printf '  %s‣%s graph-easy not found — install it to draw the real graph as\n' "${YEL:-}" "${RST:-}"
    printf '     ASCII box-art in the terminal:\n'
    printf '       Ubuntu/Debian: sudo apt-get install libgraph-easy-perl\n'
    printf '       macOS / other: cpan Graph::Easy\n'
    printf '  %s‣%s meanwhile, use  --mermaid  (no dependency) for a text graph.\n' "${YEL:-}" "${RST:-}"
    return 0
  fi

  # Feed graph-easy the same DOT we generate for PNG/SVG.
  if declare -F ip_build_dot >/dev/null 2>&1; then
    ip_build_dot | graph-easy --from=dot --as=boxart 2>/dev/null
  else
    printf '  %s‣%s internal error: ip_build_dot unavailable\n' "${YEL:-}" "${RST:-}"
  fi
}
