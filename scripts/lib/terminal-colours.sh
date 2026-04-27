# scripts/lib/terminal-colours.sh
#!/usr/bin/env bash
# ==============================================================================
# Terminal colour helpers
# ==============================================================================

uc() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

RESET=$'\033[0m'
BOLD=$'\033[1m'

get_rgb() {
  local key
  key="$(uc "$1")"

  case "$key" in
    PEACH) echo "250;179;135" ;;
    BLUE) echo "137;180;250" ;;
    GREEN) echo "166;227;161" ;;
    YELLOW) echo "249;226;175" ;;
    RED) echo "243;139;168" ;;
    MAUVE) echo "203;166;247" ;;
    TEXT) echo "205;214;244" ;;
    *) echo "205;214;244" ;;
  esac
}

fg_colour() {
  if [ -n "${NO_COLOR:-}" ]; then
    return 0
  fi

  printf '\033[38;2;%sm' "$(get_rgb "$1")"
}

print_section_header() {
  local title="$1"
  local colour="${2:-PEACH}"

  printf '\n'
  printf '%b  ________________________________________________________________  %b\n' "$(fg_colour "$colour")" "$RESET"
  printf '%b      %s                        %b\n' "$(fg_colour "$colour")" "$title" "$RESET"
  printf '%b  ________________________________________________________________  %b\n' "$(fg_colour "$colour")" "$RESET"
  printf '\n'
}