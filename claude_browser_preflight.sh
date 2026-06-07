#!/usr/bin/env bash
# ─── claude_browser_preflight.sh ─────────────────────────────────────────────
#
# PURPOSE
#   Shared preflight check for claude_browser_extension.sh and
#   claude_browser_extension_2.sh. Verifies that the tooling needed to BUILD a
#   signable .xpi is installed; prints install recommendations for whatever is
#   missing; HARD-FAILS (exit 1) if `web-ext` is not callable. On success, sets
#   and exports environment variables the caller uses for packaging.
#
# WHY web-ext IS REQUIRED (not optional)
#   The whole point of these scripts is to produce a Firefox extension that
#   can be PERMANENTLY installed. Permanence on stock Release/Beta Firefox
#   requires Mozilla-signing the .xpi, which is done via `web-ext sign`. Even
#   on Nightly/Dev/ESR (where signing can be skipped via about:config), the
#   packaging step needs to produce a structurally valid .xpi — `web-ext build`
#   does that with manifest validation; raw `zip` doesn't catch manifest errors.
#   Requiring web-ext keeps the build and the sign paths identical.
#
# HOW IT IS USED
#   The two extension scripts source this file early, right after
#   `set -euo pipefail`:
#       HERE="$(cd "$(dirname "$0")" && pwd)"
#       . "$HERE/claude_browser_preflight.sh"
#   On success, the caller can rely on:
#       PACKAGER             — always "web-ext" when this returns
#       SIGNING_AVAILABLE    — always 1 when this returns
#       HAS_NODE / HAS_NPM / HAS_WEBEXT / HAS_ZIP / HAS_PYTHON3   (0|1)
#       NODE_VER / NPM_VER / WEBEXT_VER                          (strings or "")
#   On failure (web-ext absent), this script exits 1 from inside the sourced
#   context, killing the caller — by design, so the user fixes their toolchain
#   before getting a half-built extension.
#
# STANDALONE USE
#   Running this file directly (`./claude_browser_preflight.sh`) just prints
#   the status report and exits with 0 (ok) or 1 (web-ext missing). Useful
#   for a quick "am I set up?" check without rebuilding the extensions.
# ─────────────────────────────────────────────────────────────────────────────

# Don't `set -e` here when sourced — the caller's `set -euo pipefail` is already
# in effect; we use explicit checks so the failure path is clearly visible.

# ─── detect tools ────────────────────────────────────────────────────────────
_pf_has() { command -v "$1" >/dev/null 2>&1; }

HAS_NODE=0;    NODE_VER=""
HAS_NPM=0;     NPM_VER=""
HAS_WEBEXT=0;  WEBEXT_VER=""
HAS_ZIP=0
HAS_PYTHON3=0

if _pf_has node;    then HAS_NODE=1;   NODE_VER="$(node --version 2>/dev/null || true)"; fi
if _pf_has npm;     then HAS_NPM=1;    NPM_VER="$(npm --version 2>/dev/null || true)";   fi
if _pf_has web-ext; then
  # Confirm it actually runs (catches "binary present, node missing" weirdness)
  if WEBEXT_VER="$(web-ext --version 2>/dev/null | head -1)" && [ -n "$WEBEXT_VER" ]; then
    HAS_WEBEXT=1
  fi
fi
if _pf_has zip;     then HAS_ZIP=1;     fi
if _pf_has python3; then HAS_PYTHON3=1; fi

# ─── print status table ──────────────────────────────────────────────────────
_pf_mark() { [ "$1" = 1 ] && echo "✓ FOUND" || echo "✗ MISSING"; }

echo "──── preflight: claude browser extension tooling ────────────────────────"
printf "  %-10s %-10s %s\n" "node"    "$(_pf_mark "$HAS_NODE")"    "${NODE_VER}"
printf "  %-10s %-10s %s\n" "npm"     "$(_pf_mark "$HAS_NPM")"     "${NPM_VER}"
printf "  %-10s %-10s %s\n" "web-ext" "$(_pf_mark "$HAS_WEBEXT")"  "${WEBEXT_VER}"
printf "  %-10s %-10s %s\n" "zip"     "$(_pf_mark "$HAS_ZIP")"     "(fallback, unused when web-ext present)"
printf "  %-10s %-10s %s\n" "python3" "$(_pf_mark "$HAS_PYTHON3")" "(fallback, unused when web-ext present)"
echo "─────────────────────────────────────────────────────────────────────────"

# ─── install recommendations for anything missing ────────────────────────────
_pf_recommend() {
  cat >&2 <<RECO

INSTALL RECOMMENDATIONS
═══════════════════════

To enable web-ext (and signing for permanent Firefox install), install:

  Step 1 — Node.js + npm (npm ships with Node):
RECO

  if [ "$HAS_NODE" = 0 ] || [ "$HAS_NPM" = 0 ]; then
    cat >&2 <<'RECO'
    Linux (Debian / Ubuntu, quick path — older Node):
      sudo apt update && sudo apt install -y nodejs npm

    Linux (any distro, current Node via nvm — RECOMMENDED):
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      # then re-open the shell, or: source ~/.nvm/nvm.sh
      nvm install --lts
      nvm use --lts

    macOS:
      brew install node              # gets npm too

    Windows (Git Bash / WSL / PowerShell):
      Install Node.js LTS from https://nodejs.org  →  re-open the shell.

RECO
  else
    cat >&2 <<RECO
    Already installed:  node ${NODE_VER}  /  npm ${NPM_VER}.   Skip to step 2.

RECO
  fi

  cat >&2 <<'RECO'
  Step 2 — web-ext (Mozilla's extension build + sign CLI):
      npm install -g web-ext

  Verify:
      node --version
      npm  --version
      web-ext --version

  Then re-run this script.
═══════════════════════════════════════════════════════════════════════════

RECO
}

# ─── decide pass/fail ────────────────────────────────────────────────────────
PACKAGER=""
SIGNING_AVAILABLE=0

if [ "$HAS_WEBEXT" = 1 ]; then
  PACKAGER="web-ext"
  SIGNING_AVAILABLE=1
  echo "✓ preflight OK — packager: web-ext (signing available via 'web-ext sign')."
  echo
else
  echo "✗ PREFLIGHT FAILED — web-ext is required to build a signable .xpi." >&2
  _pf_recommend

  # If web-ext is missing but a fallback packager exists, note it for the curious
  if [ "$HAS_ZIP" = 1 ] || [ "$HAS_PYTHON3" = 1 ]; then
    cat >&2 <<'NOTE'
NOTE: a fallback packager (zip or python3) IS available on this system, but it
is intentionally not used. A raw zip skips manifest validation and cannot sign,
so the produced .xpi would only install on Nightly/Dev/ESR with signature
enforcement disabled — exactly the failure mode this preflight exists to prevent.
If you really want the fallback behavior anyway, edit this preflight to set
PACKAGER=zip / python3 and remove the exit below at your own risk.

NOTE
  fi

  # exit 1 propagates out of the sourced context, killing the caller — intended.
  exit 1
fi

# ─── export for caller ───────────────────────────────────────────────────────
export HAS_NODE HAS_NPM HAS_WEBEXT HAS_ZIP HAS_PYTHON3
export NODE_VER NPM_VER WEBEXT_VER
export PACKAGER SIGNING_AVAILABLE

# Allow standalone invocation: `./claude_browser_preflight.sh` should exit 0
# when reached here. When sourced, the caller continues; the trailing `return`
# (if sourced) or implicit exit 0 (if executed) handles both.
return 0 2>/dev/null || exit 0
