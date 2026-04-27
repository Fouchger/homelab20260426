#!/usr/bin/env bash
# ==============================================================================
# Homelab Setup Banner
# ==============================================================================
#
# File: scripts/banner/banner.sh
# Purpose:
#   Prints the Homelab Setup banner with Catppuccin-inspired terminal colours.
#
# Usage:
#   ./scripts/banner.sh
#
# Optional environment variables:
#   CATPPUCCIN_FLAVOUR=LATTE|FRAPPE|MACCHIATO|MOCHA
#   NO_COLOR=1
#
# Notes:
#   - Defaults to LATTE if no flavour is provided.
#   - Disables colour automatically when NO_COLOR is set.
#
# ==============================================================================



# ---------------------------------------
# Simple utils (define BEFORE traps)
# ---------------------------------------
uc() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------
# Catppuccin colours + helpers
# ---------------------------------------
FLAVOUR="${CATPPUCCIN_FLAVOUR:-LATTE}"; FLAVOUR="$(uc "$FLAVOUR")"
case "$FLAVOUR" in LATTE|FRAPPE|MACCHIATO|MOCHA) : ;; *) FLAVOUR="LATTE";; esac

get_rgb() {
  local key flavour
  key="$(uc "$1")"; flavour="$FLAVOUR"
  case "${flavour}:${key}" in
    LATTE:ROSEWATER) echo "220;138;120" ;;  LATTE:FLAMINGO)  echo "221;120;120" ;;
    LATTE:PINK)      echo "234;118;203" ;;  LATTE:MAUVE)     echo "136;57;239"  ;;
    LATTE:RED)       echo "210;15;57"   ;;  LATTE:MAROON)    echo "230;69;83"   ;;
    LATTE:PEACH)     echo "254;100;11"  ;;  LATTE:YELLOW)    echo "223;142;29"  ;;
    LATTE:GREEN)     echo "64;160;43"   ;;  LATTE:TEAL)      echo "23;146;153"  ;;
    LATTE:SKY)       echo "4;165;229"   ;;  LATTE:SAPPHIRE)  echo "32;159;181"  ;;
    LATTE:BLUE)      echo "30;102;245"  ;;  LATTE:LAVENDER)  echo "114;135;253" ;;
    LATTE:TEXT)      echo "76;79;105"   ;;  LATTE:SUBTEXT1)  echo "92;95;119"   ;;
    LATTE:SUBTEXT0)  echo "108;111;133" ;;  LATTE:OVERLAY2)  echo "124;127;147" ;;
    LATTE:OVERLAY1)  echo "140;143;161" ;;  LATTE:OVERLAY0)  echo "156;160;176" ;;
    LATTE:SURFACE2)  echo "172;176;190" ;;  LATTE:SURFACE1)  echo "188;192;204" ;;
    LATTE:SURFACE0)  echo "204;208;218" ;;  LATTE:BASE)      echo "239;241;245" ;;
    LATTE:MANTLE)    echo "230;233;239" ;;  LATTE:CRUST)     echo "220;224;232" ;;
    FRAPPE:ROSEWATER) echo "242;213;207" ;; FRAPPE:FLAMINGO)  echo "238;190;190" ;;
    FRAPPE:PINK)      echo "244;184;228" ;; FRAPPE:MAUVE)     echo "202;158;230" ;;
    FRAPPE:RED)       echo "231;130;132" ;; FRAPPE:MAROON)    echo "234;153;156" ;;
    FRAPPE:PEACH)     echo "239;159;118" ;; FRAPPE:YELLOW)    echo "229;200;144" ;;
    FRAPPE:GREEN)     echo "166;209;137" ;; FRAPPE:TEAL)      echo "129;200;190" ;;
    FRAPPE:SKY)       echo "153;209;219" ;; FRAPPE:SAPPHIRE)  echo "133;193;220" ;;
    FRAPPE:BLUE)      echo "140;170;238" ;; FRAPPE:LAVENDER)  echo "186;187;241" ;;
    FRAPPE:TEXT)      echo "198;208;245" ;; FRAPPE:SUBTEXT1)  echo "181;191;226" ;;
    FRAPPE:SUBTEXT0)  echo "165;173;206" ;; FRAPPE:OVERLAY2)  echo "148;156;187" ;;
    FRAPPE:OVERLAY1)  echo "131;139;167" ;; FRAPPE:OVERLAY0)  echo "115;121;148" ;;
    FRAPPE:SURFACE2)  echo "98;104;128"  ;; FRAPPE:SURFACE1)  echo "81;87;109"   ;;
    FRAPPE:SURFACE0)  echo "65;69;89"    ;; FRAPPE:BASE)      echo "48;52;70"    ;;
    FRAPPE:MANTLE)    echo "41;44;60"    ;; FRAPPE:CRUST)     echo "35;38;52"    ;;
    MACCHIATO:ROSEWATER) echo "244;219;214" ;; MACCHIATO:FLAMINGO)  echo "240;198;198" ;;
    MACCHIATO:PINK)      echo "245;189;230" ;; MACCHIATO:MAUVE)     echo "198;160;246" ;;
    MACCHIATO:RED)       echo "237;135;150" ;; MACCHIATO:MAROON)    echo "238;153;160" ;;
    MACCHIATO:PEACH)     echo "245;169;127" ;; MACCHIATO:YELLOW)    echo "238;212;159" ;;
    MACCHIATO:GREEN)     echo "166;218;149" ;; MACCHIATO:TEAL)      echo "139;213;202" ;;
    MACCHIATO:SKY)       echo "145;215;227" ;; MACCHIATO:SAPPHIRE)  echo "125;196;228" ;;
    MACCHIATO:BLUE)      echo "138;173;244" ;; MACCHIATO:LAVENDER)  echo "183;189;248" ;;
    MACCHIATO:TEXT)      echo "202;211;245" ;; MACCHIATO:SUBTEXT1)  echo "184;192;224" ;;
    MACCHIATO:SUBTEXT0)  echo "165;173;203" ;; MACCHIATO:OVERLAY2)  echo "147;154;183" ;;
    MACCHIATO:OVERLAY1)  echo "128;135;162" ;; MACCHIATO:OVERLAY0)  echo "110;115;141" ;;
    MACCHIATO:SURFACE2)  echo "91;96;120"   ;; MACCHIATO:SURFACE1)  echo "73;77;100"   ;;
    MACCHIATO:SURFACE0)  echo "54;58;79"    ;; MACCHIATO:BASE)      echo "36;39;58"    ;;
    MACCHIATO:MANTLE)    echo "30;32;48"    ;; MACCHIATO:CRUST)     echo "24;25;38"    ;;
    MOCHA:ROSEWATER) echo "245;224;220" ;;  MOCHA:FLAMINGO)  echo "242;205;205" ;;
    MOCHA:PINK)      echo "245;194;231" ;;  MOCHA:MAUVE)     echo "203;166;247" ;;
    MOCHA:RED)       echo "243;139;168" ;;  MOCHA:MAROON)    echo "235;160;172" ;;
    MOCHA:PEACH)     echo "250;179;135" ;;  MOCHA:YELLOW)    echo "249;226;175" ;;
    MOCHA:GREEN)     echo "166;227;161" ;;  MOCHA:TEAL)      echo "148;226;213" ;;
    MOCHA:SKY)       echo "137;220;235" ;;  MOCHA:SAPPHIRE)  echo "116;199;236" ;;
    MOCHA:BLUE)      echo "137;180;250" ;;  MOCHA:LAVENDER)  echo "180;190;254" ;;
    MOCHA:TEXT)      echo "205;214;244" ;;  MOCHA:SUBTEXT1)  echo "186;194;222" ;;
    MOCHA:SUBTEXT0)  echo "166;173;200" ;;  MOCHA:OVERLAY2)  echo "147;153;178" ;;
    MOCHA:OVERLAY1)  echo "127;132;156" ;;  MOCHA:OVERLAY0)  echo "108;112;134" ;;
    MOCHA:SURFACE2)  echo "88;91;112"   ;;  MOCHA:SURFACE1)  echo "69;71;90"    ;;
    MOCHA:SURFACE0)  echo "49;50;68"    ;;  MOCHA:BASE)      echo "30;30;46"    ;;
    MOCHA:MANTLE)    echo "24;24;37"    ;;  MOCHA:CRUST)     echo "17;17;27"    ;;
    *) echo "128;128;128" ;;
  esac
}

# --- Truecolour detection (conservative) ---
_supports_truecolor() {
  # Explicit opt-out takes priority
  if [ -n "${NO_COLOR:-}" ]; then return 1; fi
  # Explicit opt-in for automation or known-good envs
  if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then return 0; fi
  # Heuristic: known truecolour terminals (best-effort)
  if command -v tput >/dev/null 2>&1; then
    local colors; colors="$(tput colors 2>/dev/null || echo 0)"
    [ "$colors" -ge 256 ] && return 0
  fi
  return 1
}

set_truecolor() {
if _supports_truecolor; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; ITALIC=$'\033[3m'; UNDERLINE=$'\033[4m'
  fg() { printf "\033[38;2;%sm" "$(get_rgb "$1")"; }
  bg() { printf "\033[48;2;%sm" "$(get_rgb "$1")"; }
  off(){ printf "%b" "$RESET"; }
else
  RESET=""; BOLD=""; DIM=""; ITALIC=""; UNDERLINE=""
  fg(){ :; }; bg(){ :; }; off(){ :; }
fi
}
set_truecolor
# ensure child shells inherit these
export FLAVOUR RESET BOLD DIM ITALIC UNDERLINE

# ---------------------------------------
# Banner
# ---------------------------------------
print_banner() {
  printf '\n'
  printf '%b  ██╗  ██╗ ██████╗ ███╗   ███╗███████╗██╗      █████╗ ██████╗     ███████╗███████╗████████╗██╗   ██╗██████╗ %b Homelab Setup %b\n' "$(fg RED)" "$(fg PEACH)" "$RESET"
  printf '%b  ██║  ██║██╔═══██╗████╗ ████║██╔════╝██║     ██╔══██╗██╔══██╗    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗%b by GertGerber %b\n' "$(fg RED)" "$(fg BLUE)" "$RESET"
  printf '%b  ███████║██║   ██║██╔████╔██║█████╗  ██║     ███████║██████╔╝    ███████╗█████╗     ██║   ██║   ██║██████╔╝%b Setup your Proxmox environment %b\n' "$(fg RED)" "$(fg MAUVE)" "$RESET"
  printf '%b  ██╔══██║██║   ██║██║╚██╔╝██║██╔══╝  ██║     ██╔══██║██╔══██╗    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ %b Enjoy homelab! 🚀 %b\n' "$(fg RED)" "$(fg YELLOW)" "$RESET"
  printf '%b  ██║  ██║╚██████╔╝██║ ╚═╝ ██║███████╗███████╗██║  ██║██████╔╝    ███████║███████╗   ██║   ╚██████╔╝██║     %b Have fun with roles! 🎉 %b\n' "$(fg RED)" "$(fg GREEN)" "$RESET"
  printf '%b  ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚═════╝     ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     %b\n' "$(fg RED)" "$RESET"
  printf '\n'
}

print_banner
