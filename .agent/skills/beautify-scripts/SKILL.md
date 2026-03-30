---
name: Beautify Bash Scripts
description: Standardizes the ANSI color palette, helper print functions, an ASCII banner script, and a step-by-step layout for all shell scripts in this project.
---

# Bash Script Formatting Guidelines

Whenever you create a new bash script (`*.sh`) in this project or are asked to refactor an existing one, you MUST strictly format it to match the visual identity established in `scripts/bootstrap.sh` and `scripts/test-scenarios.sh`.

Follow these rules when writing bash scripts:

### 1. File Header
Always start with the shebang and a header comment block explaining what the script does.
```bash
#!/usr/bin/env bash
# =============================================================================
# script-name.sh — Brief description of what this script does.
# =============================================================================
set -euo pipefail
```

### 2. Standardized ANSI Color Palette
Include the strict color palette at the top of the script:
```bash
# ── ANSI color & style palette ────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

BG_BLUE="\033[44m"
BG_CYAN="\033[46m"
BG_GREEN="\033[42m"
BG_RED="\033[41m"

# Semantic aliases
COLOR_STEP="${BOLD}${CYAN}"
COLOR_OK="${BOLD}${GREEN}"
COLOR_WARN="${BOLD}${YELLOW}"
COLOR_ERR="${BOLD}${RED}"
COLOR_DIM="${DIM}${WHITE}"
COLOR_KEY="${BOLD}${MAGENTA}"
```

### 3. Standard UI Helper Functions
Always include these standard helper functions to log script states:
```bash
# ── Helper printers ───────────────────────────────────────────────────────────
divider() {
  echo -e "${COLOR_DIM}  ──────────────────────────────────────────────────────────────${RESET}"
}

step() {
  local num="$1" total="$2" label="$3"
  echo ""
  divider
  echo -e "  ${COLOR_STEP}▶  STEP ${num}/${total}${RESET}  ${BOLD}${label}${RESET}"
  divider
}

info()    { echo -e "     ${COLOR_DIM}→${RESET}  $*"; }
success() { echo -e "     ${COLOR_OK}✔${RESET}  $*"; }
warn()    { echo -e "     ${COLOR_WARN}⚠${RESET}  $*"; }
fail()    { echo -e "     ${COLOR_ERR}✘  ERROR: $*${RESET}" >&2; exit 1; }
```

### 4. Custom Banner (Optional)
If it's an important entrypoint script, you should generate a bespoke ASCII banner matching the theme from `bootstrap.sh`.

### 5. Execution Steps
Structure execution flow in visual steps using `step [current] [total] [description]`. Use the `info` helper to describe the action before taking it, and catch output using `success` or `fail` where possible.
Always segregate steps using the uniform padding line:
```bash
# ═════════════════════════════════════════════════════════════════════════════
step 1 3 "Doing the objective"

info "Gathering details..."
# command >/dev/null || fail "Failed"
success "Gathered gracefully"
```
