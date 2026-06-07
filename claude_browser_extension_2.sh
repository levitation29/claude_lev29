#!/usr/bin/env bash
# ─── claude_browser_extension_2.sh ───────────────────────────────────────────
#
# PURPOSE
#   A pared-down sibling of claude_browser_extension.sh. It builds a local,
#   unpacked Manifest V3 browser extension that injects ONE small draggable HUD
#   onto every claude.ai page. The HUD has three action icons and does nothing
#   else (no network monitor, no audit/probe/histogram):
#
#     📝  With Settings ▸ General open (modal OR full page), fetch
#         command_2_preferences.notes from GitHub AT RUNTIME and fill "Instructions
#         for Claude" with it. Nothing is baked in. It targets a <textarea> only
#         (the chat composer is a contenteditable <div>, so it is NEVER touched);
#         saves via the dialog's Save button if present, else blurs to autosave.
#         (If Settings isn't open, it says so and does nothing.)
#     🏷  With Settings ▸ Billing open, read the plan name into the HUD.
#     📋  List the command shortcuts parsed from the fetched prefs (one per line);
#         click one to insert it into the claude.ai composer. A command is any
#         backtick `token` or bold **token** that is a bare command id — so it
#         catches bold-defined commands (zip-project, unzip-project) but skips
#         shell snippets, arg forms, and bold section labels (**Naming:**).
#
# WHAT THIS SCRIPT CREATES
#   claude-hud2-extension/
#     manifest.json     — Manifest V3 manifest (Chrome / Firefox)
#     claude_hud2.js    — the HUD + the three actions
#   web-ext-artifacts/
#     *.zip             — packaged extension (built by `web-ext build`)
#     *.xpi             — same bytes as the .zip; named .xpi so Firefox's
#                         "Install Add-on From File..." accepts it
#
# WHY ISOLATED WORLD + host_permissions (not MAIN world)
#   The 📝 action fetch()es the prefs from raw.githubusercontent.com. A MAIN-world
#   fetch would be blocked by claude.ai's connect-src CSP. An ISOLATED-world
#   content script whose target host is in "host_permissions" fetches that host
#   with CORS bypassed and is NOT subject to the page CSP. The React value-setter
#   (native prototype setter + input event on the shared DOM element) still works
#   from the isolated world, so dropping MAIN world costs nothing here.
#   (Trade-off: window.claudeHud2 lives on the isolated window, not the page
#   console — the two buttons are the interface.)
#
# CHANGING THE PREFS SOURCE
#   The raw URL is the ONLY embedded value, and THIS script is the single source
#   of truth (no generator). To point elsewhere, edit the PREFS_URL constant in
#   the claude_hud2.js heredoc below — use a raw.githubusercontent.com URL, not a
#   github.com/.../blob/... one. To change the prefs CONTENT, just edit the file
#   in the GitHub repo; no change here is needed.
#
# CAVEATS (read before relying on it)
#   1. Console helpers are NOT on the page console. Because this runs in the
#      ISOLATED world (required for the cross-origin prefs fetch), window.claudeHud2
#      lives on the extension's isolated context, not the page's window — typing
#      claudeHud2.show()/destroy()/reloadPrefs() in the DevTools console returns
#      "undefined". The two HUD buttons are the interface; to bring the panel back
#      after hiding it with ×, refresh claude.ai (the content script re-runs on
#      load).
#   2. The 📝 fetch needs the prefs file PUBLIC at PREFS_URL. If the repo goes
#      private, or the path/branch/filename changes, 📝 reports
#      "✗ fetch failed: HTTP 404" (or similar). Fix by editing PREFS_URL below.
#      A private repo will NOT work — the content script sends no credentials.
#   3. 📝/🏷 act on the settings view you have OPEN (open Settings ▸ General or
#      ▸ Billing yourself first); it works whether Settings renders as a modal or
#      as a full page. claude.ai does not reliably open Settings from a URL-hash
#      change, so this build does not try to auto-open it. Matching is best-effort
#      against claude.ai's CURRENT markup (a <textarea> named/under "Instructions
#      for Claude"; Save button text/aria /save/i; plan text "<tier> plan"); if the
#      DOM changes, the HUD status line says so. 📝 only ever targets a <textarea>,
#      and the chat composer is a contenteditable <div> — so it can NEVER write to
#      the chat box.
#   4. The 📋 command list is INFERRED from the prefs prose: a command is any
#      backtick `token` or bold **token** that is a bare command id. It now tracks
#      both markups (so bold-defined zip-project / unzip-project are caught), but a
#      command written some other way (e.g. a bare word in a table, no backtick or
#      bold) will NOT be listed. The robust-but-format-changing alternative is a
#      dedicated "## COMMANDS" block in the notes that the extension parses
#      verbatim. A small blocklist drops shell/field stragglers (cp, rm, unzip,
#      working_name, …); edit CMD_BLOCK below if the prose adds new false hits.
#   5. 📋 composer insertion uses the SAME best-effort ProseMirror path as
#      claude_browser_extension.sh (focus the editor → execCommand insertText,
#      verify against the DOM, else a synthetic beforeinput, else copy to
#      clipboard). It inherits the same fragility: if claude.ai changes its editor
#      the insert may fail — the HUD status line reports it and the command is left
#      on the clipboard to paste manually.
#
# HOW TO RUN
#   Place claude_browser_preflight.sh in the SAME directory as this script.
#   The shared preflight verifies that node + npm + web-ext are installed (and
#   prints install instructions if not). Then:
#
#     chmod +x claude_browser_extension_2.sh claude_browser_preflight.sh
#     ./claude_browser_extension_2.sh
#
#   On success this produces the unpacked folder, a packaged .zip, and an .xpi
#   ready for direct install (see the FIREFOX install paths below).
#
# SEE ALSO
#   browser_extension_signing.md (next to this script) — complete guide to
#   Firefox signing and AMO distribution. Consult it for all signing options.
#
# INSTALL (Chrome 111+ / Firefox 109+ for MV3 host_permissions)
#   Chrome:  chrome://extensions → enable Developer mode → Load unpacked →
#            pick the claude-hud2-extension/ folder. Refresh claude.ai.
#            (It will ask to read data on raw.githubusercontent.com — that is the
#            prefs fetch.)
#   Firefox: choice of TWO install paths depending on how long you want it to last
#            (Firefox treats add-ons very differently from Chrome here):
#
#       (1) TEMPORARY — about:debugging#/runtime/this-firefox → Load Temporary
#           Add-on → pick claude-hud2-extension/manifest.json. Refresh claude.ai.
#           Wiped when Firefox closes (also on crash). Good for one session.
#       (2) PERMANENT, UNSIGNED — Nightly / Developer Edition / ESR ONLY
#           about:config → xpinstall.signatures.required = false → about:addons →
#           gear → "Install Add-on From File..." → the .xpi (zip renamed). Stays
#           until you remove it. Stock Release/Beta IGNORE this pref.
#
#       For signing / AMO distribution options: see browser_extension_signing.md.
#
#   The "Claude HUD" panel appears top-right. Drag it; × hides it for the page
#   (refresh claude.ai to bring it back — see CAVEAT 1 re: console helpers).
#
# USAGE
#   📝  Open Settings ▸ General, then click 📝 → it fetches the prefs from GitHub,
#       clears the box, pastes, and clicks Save (or blurs to autosave). The fetch
#       is cached per page load — refresh claude.ai to pull updated prefs.
#   🏷  Open Settings ▸ Billing, then click 🏷 → the HUD shows e.g. "🏷 Max plan".
#   📋  Click 📋 → the HUD fetches the prefs and lists every command shortcut
#       (filter box + one button per command). Click a command → it is inserted
#       into the message composer (focus it first; falls back to clipboard).
#   Each action also logs its result to the DevTools console ("[Claude HUD 2]").
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─── preflight: required tooling ─────────────────────────────────────────────
# Source the shared preflight (must sit next to this script). It hard-fails
# (exit 1) if web-ext is missing, with install instructions for node/npm/web-ext.
# On success it exports: PACKAGER, SIGNING_AVAILABLE, HAS_*, *_VER.
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$HERE/claude_browser_preflight.sh" ]; then
  cat >&2 <<EOF
ERROR: claude_browser_preflight.sh not found next to this script.
Expected at: $HERE/claude_browser_preflight.sh
Put all three files (claude_browser_extension.sh, claude_browser_extension_2.sh,
and claude_browser_preflight.sh) in the same directory and re-run.
EOF
  exit 1
fi
# shellcheck disable=SC1091
. "$HERE/claude_browser_preflight.sh"

EXTDIR="claude-hud2-extension"
echo "Creating extension folder: $EXTDIR/"
mkdir -p "$EXTDIR"

# ─── manifest.json ────────────────────────────────────────────────────────────
# host_permissions lets the isolated content script fetch the prefs from GitHub
# (CORS-bypassed, not subject to claude.ai's CSP). No "world":"MAIN".
# browser_specific_settings.gecko lets Firefox load it; Chrome ignores that key.
#   .id                              — Stable, explicit add-on ID. Required for
#                                      AMO signing (see browser_extension_signing.md).
#   .data_collection_permissions     — Required by AMO (since 2025-11-03). Value
#                                      ["none"] declares no personal data collected
#                                      (truthful — the prefs fetch sends no browser
#                                      data). Firefox shows this at install time.
cat > "$EXTDIR/manifest.json" << 'MANIFEST_EOF'
{
  "manifest_version": 3,
  "name": "Claude HUD 2 — Actions",
  "version": "2.8",
  "description": "A minimal draggable HUD on claude.ai with three action icons: with Settings ▸ General open, fill the Instructions box from GitHub (dialog-scoped); with Settings ▸ Billing open, read the plan name; and list command shortcuts that insert into the composer.",
  "host_permissions": ["https://raw.githubusercontent.com/*"],
  "content_scripts": [
    {
      "matches": ["https://claude.ai/*"],
      "js": ["claude_hud2.js"],
      "run_at": "document_idle"
    }
  ],
  "browser_specific_settings": {
    "gecko": {
      "id": "claude-hud2@local",
      "strict_min_version": "109.0",
      "data_collection_permissions": { "required": ["none"] }
    }
  }
}
MANIFEST_EOF
echo "  wrote manifest.json"

# ─── claude_hud2.js ───────────────────────────────────────────────────────────
# Quoted heredoc: no shell expansion; the JS is written verbatim.
cat > "$EXTDIR/claude_hud2.js" << 'JS_EOF'
// ─── Claude HUD 2 — two action icons ────────────────────────────────────────
//
// A minimal, draggable on-page panel for claude.ai with EXACTLY two buttons —
// no network monitoring, no audit/probe/histogram. Derived from
// claude_browser_extension.sh: only the HUD scaffolding (css / mkBtn /
// makeDraggable / the panel) is kept; everything else is removed.
//
//   📝  Fill Settings ▸ General "Instructions for Claude" with your preferences,
//       FETCHED AT RUNTIME from GitHub (PREFS_URL below) — nothing is baked in.
//       Acts only inside an open settings dialog; saves via the Save button if
//       present, else blurs to autosave.
//   🏷  Read the plan name off Settings ▸ Billing and show it in the HUD.
//
// WORLD: this runs in the extension's ISOLATED world (manifest has no
// "world":"MAIN"). That is deliberate: a MAIN-world fetch to GitHub would be
// blocked by claude.ai's connect-src CSP, whereas an isolated content-script
// fetch to a host listed in host_permissions bypasses CORS and the page CSP.
// The React value-setter (native prototype setter + input event on the shared
// DOM element) still works from the isolated world.
(function () {
  'use strict';
  if (window.__claudeHud2) return;            // singleton across re-injects
  window.__claudeHud2 = true;

  // ── where the preferences live (fetched at click time, cached per session) ──
  const PREFS_URL = "https://raw.githubusercontent.com/levitation29/claude_lev29/main/command_2_preferences.notes";
  let prefsCache = null;
  async function loadPrefs() {
    if (prefsCache != null) return prefsCache;
    const res = await fetch(PREFS_URL, { cache: 'no-store' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const text = await res.text();
    if (!text || !text.trim()) throw new Error('empty response');
    prefsCache = text;
    return text;
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  function setReactValue(el, value) {
    const proto = el.tagName === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  // Visible settings-style modals only — so we never touch the chat composer.
  function openDialogs() {
    return [].slice.call(document.querySelectorAll('[role="dialog"], [aria-modal="true"]'))
             .filter(function (d) { return d.offsetParent !== null; });
  }

  // ── action 1: fetch prefs, clear + paste into the instructions box, then save
  function findInstructionsBox() {
    // The chat composer is a contenteditable <div>, NEVER a <textarea> — so
    // scanning textareas can't hit it. Settings can render as a modal OR a full
    // page, so look inside an open dialog first, else the whole document.
    const dialogs = openDialogs();
    const scopes = dialogs.length ? dialogs : [document];
    for (let i = 0; i < scopes.length; i++) {
      const tas = [].slice.call(scopes[i].querySelectorAll('textarea'))
                    .filter(function (t) { return t.offsetParent !== null; });
      if (!tas.length) continue;
      // 1) textarea whose own attributes name it
      const byAttr = tas.find(function (t) {
        const hay = (t.placeholder || '') + ' ' + (t.getAttribute('aria-label') || '') +
                    ' ' + (t.name || '') + ' ' + (t.id || '');
        return /instruction/i.test(hay);
      });
      if (byAttr) return byAttr;
      // 2) textarea sitting under an "Instructions for Claude" heading/label
      const byLabel = tas.find(function (t) {
        let el = t.parentElement;
        for (let up = 0; up < 5 && el; up++, el = el.parentElement) {
          if (/instructions for claude/i.test(el.textContent || '')) return true;
        }
        return false;
      });
      if (byLabel) return byLabel;
      // 3) lone visible textarea in scope = the box
      if (tas.length === 1) return tas[0];
    }
    return null;   // nothing that looks like the instructions box
  }
  function clickSaveIn(scope) {
    const btns = [].slice.call((scope || document).querySelectorAll('button, [role="button"]'))
      .filter(function (b) {
        if (b.offsetParent === null || b.disabled) return false;
        const hay = ((b.textContent || '') + ' ' + (b.getAttribute('aria-label') || '')).trim();
        return /\bsave\b/i.test(hay);
      });
    if (btns.length) { btns[0].click(); return true; }
    return false;
  }
  async function fillInstructions() {
    const box = findInstructionsBox();
    if (!box) return '\u2717 open Settings \u25b8 General first, then click \ud83d\udcdd (won\u2019t touch the chat box)';
    let prefs;
    try { prefs = await loadPrefs(); }
    catch (e) { return '\u2717 fetch failed: ' + (e && e.message ? e.message : String(e)); }
    try {
      box.focus();
      setReactValue(box, '');        // clear
      setReactValue(box, prefs);     // paste
    } catch (e) {
      return '\u2717 could not set value: ' + (e && e.message ? e.message : String(e));
    }
    const scope = box.closest('[role="dialog"], [aria-modal="true"]') || document;
    box.blur();                                  // "click outside" -> autosave
    const saved = clickSaveIn(scope);
    const nbytes = new TextEncoder().encode(prefs).length;   // UTF-8 bytes = wc -c
    return '\u2713 wrote ' + nbytes + ' bytes (from GitHub)' +
           (saved ? ' + clicked Save' : ' \u2014 blurred to autosave');
  }

  // ── action 2: read the plan name off the billing popup ─────────────────────
  function readPlan() {
    const PLAN_RE = /\b(Free|Pro|Max|Team|Enterprise)\b(?:\s+(?:5x|20x))?\s*plan/i;
    const dialogs = openDialogs();
    const roots = dialogs.length ? dialogs : [document.body];
    for (let i = 0; i < roots.length; i++) {
      const walker = document.createTreeWalker(roots[i], NodeFilter.SHOW_TEXT);
      let n;
      while ((n = walker.nextNode())) {
        const t = (n.nodeValue || '').trim();
        if (!t) continue;
        const m = t.match(PLAN_RE);
        if (m && n.parentElement && n.parentElement.offsetParent !== null) return '\ud83c\udff7 ' + m[0].trim();
      }
    }
    return '\u2717 open Settings \u25b8 Billing first, then click \ud83c\udff7';
  }

  // ── action 3: list command shortcuts from the prefs; click → composer ──────
  // A command is a backtick `token` OR a bold **token** whose WHOLE content
  // (minus a trailing colon) is a bare command id. That drops shell commands
  // (`rm -rf ...`), arg forms (`max=N`), and bold section labels (**Naming:**),
  // while catching bold-defined commands like **zip-project** / **unzip-project**.
  const CMD_BLOCK = new Set(['cp','str_replace','entry','next_entry','id','store_as',
    'turns','tools','equals','max','working_name']);
  function extractCommands(text) {
    const out = [], seen = new Set();
    const re = /`([^`]+)`|\*\*([^*]+)\*\*/g;
    let m;
    while ((m = re.exec(text))) {
      const tok = (m[1] || m[2] || '').trim().replace(/:+$/, '').trim();
      if (!/^[a-z][a-z0-9_\-]+$/.test(tok)) continue;   // whole token must be a bare command id
      if (CMD_BLOCK.has(tok) || seen.has(tok)) continue;
      seen.add(tok); out.push(tok);
    }
    return out;
  }

  // composer insert — ported from claude_browser_extension.sh (verify vs the DOM,
  // fall back to clipboard).
  function findComposer() {
    return document.querySelector('div.ProseMirror[contenteditable="true"]')
        || document.querySelector('[contenteditable="true"][role="textbox"]')
        || document.querySelector('main [contenteditable="true"]')
        || document.querySelector('[contenteditable="true"]');
  }
  function pasteToComposer(text) {
    const el = findComposer();
    if (!el) return navigator.clipboard.writeText(text)
      .then(() => '\u2717 no composer \u2014 copied "' + text + '" to clipboard')
      .catch(() => '\u2717 no composer found');
    el.focus();
    const before = el.textContent;
    try { document.execCommand('insertText', false, text); } catch (e) {}
    if (el.textContent === before) {
      try { el.dispatchEvent(new InputEvent('beforeinput',
        { inputType: 'insertText', data: text, bubbles: true, cancelable: true })); } catch (e) {}
    }
    return (el.textContent !== before)
      ? '\u2713 inserted "' + text + '" into the composer'
      : navigator.clipboard.writeText(text).then(() => '\u2717 insert refused \u2014 copied "' + text + '" instead');
  }

  // The command panel, toggled by the \ud83d\udccb header button. Reuses loadPrefs().
  let cmdPanel = null;
  async function toggleCommands() {
    if (cmdPanel) { cmdPanel.remove(); cmdPanel = null; return 'commands hidden'; }
    let cmds;
    try { cmds = extractCommands(await loadPrefs()); }
    catch (e) { return '\u2717 fetch failed: ' + (e && e.message ? e.message : String(e)); }
    if (!cmds.length) return '\u2717 no commands found in prefs';
    cmdPanel = document.createElement('div');
    css(cmdPanel, { borderTop: '1px solid rgba(108,71,255,0.4)', padding: '6px' });
    const filter = document.createElement('input');
    filter.placeholder = 'filter\u2026';
    filter.setAttribute('aria-label', 'filter commands');
    css(filter, { width: '100%', boxSizing: 'border-box', background: 'rgba(255,255,255,0.07)',
      border: '1px solid rgba(108,71,255,0.45)', color: '#fff', borderRadius: '4px',
      padding: '4px 7px', font: 'inherit', outline: 'none', marginBottom: '4px' });
    const listEl = document.createElement('div');
    css(listEl, { maxHeight: '260px', overflow: 'auto' });
    const render = (q) => {
      listEl.textContent = '';
      cmds.filter(c => !q || c.toLowerCase().indexOf(q.toLowerCase()) >= 0).forEach(c => {
        const b = document.createElement('button');
        b.textContent = c;
        css(b, { all: 'unset', display: 'block', width: '100%', boxSizing: 'border-box',
          cursor: 'pointer', color: '#cdbcff', font: '12px/1.4 ui-monospace, Menlo, monospace',
          padding: '4px 7px', borderRadius: '4px' });
        b.addEventListener('mouseenter', () => css(b, { background: 'rgba(108,71,255,0.35)', color: '#fff' }));
        b.addEventListener('mouseleave', () => css(b, { background: 'transparent', color: '#cdbcff' }));
        b.addEventListener('click', () => Promise.resolve(pasteToComposer(c)).then(setStatus));
        listEl.appendChild(b);
      });
    };
    filter.addEventListener('input', () => render(filter.value.trim()));
    render('');
    cmdPanel.appendChild(filter);
    cmdPanel.appendChild(listEl);
    hudRoot.appendChild(cmdPanel);
    return cmds.length + ' commands \u2014 click one to insert it into the composer';
  }

  // ── HUD scaffolding (lifted from claude_browser_extension.sh) ──────────────
  let hudRoot = null, hudStatus = null, hudObserver = null;
  const css = (el, props) => { for (const k in props) el.style[k] = props[k]; };

  function mkBtn(label, title, onClick) {
    const b = document.createElement('button');
    b.textContent = label;
    b.title = title;
    css(b, { all: 'unset', cursor: 'pointer', color: '#cdbcff', fontSize: '15px',
      lineHeight: '1', padding: '3px 7px', borderRadius: '4px', marginLeft: '4px' });
    b.addEventListener('mouseenter', () => css(b, { background: 'rgba(108,71,255,0.35)' }));
    b.addEventListener('mouseleave', () => css(b, { background: 'transparent' }));
    b.addEventListener('click', (e) => { e.stopPropagation(); onClick(); });
    return b;
  }

  function makeDraggable(el, handle) {
    let sx = 0, sy = 0, ox = 0, oy = 0, active = false;
    const onMove = (e) => {
      if (!active) return;
      let left = ox + (e.clientX - sx), top = oy + (e.clientY - sy);
      left = Math.max(0, Math.min(left, window.innerWidth  - el.offsetWidth));
      top  = Math.max(0, Math.min(top,  window.innerHeight - el.offsetHeight));
      el.style.left = left + 'px'; el.style.top = top + 'px';
      el.style.right = 'auto'; el.style.bottom = 'auto';
    };
    const onUp = () => {
      if (!active) return;
      active = false;
      document.removeEventListener('pointermove', onMove, true);
      document.removeEventListener('pointerup', onUp, true);
      css(handle, { cursor: 'move' });
    };
    handle.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || (e.target && e.target.tagName === 'BUTTON')) return;  // left-drag; let buttons click
      const r = el.getBoundingClientRect();
      ox = r.left; oy = r.top; sx = e.clientX; sy = e.clientY; active = true;
      css(handle, { cursor: 'grabbing' });
      document.addEventListener('pointermove', onMove, true);
      document.addEventListener('pointerup', onUp, true);
      e.preventDefault();   // no text selection while dragging
    });
  }

  function setStatus(msg) {
    if (hudStatus) hudStatus.textContent = msg;
    console.log('[Claude HUD 2]', msg);
  }

  function ensureHud() {
    if (hudRoot) return;
    hudRoot = document.createElement('div');
    css(hudRoot, {
      position: 'fixed', top: '80px', right: '12px', zIndex: '2147483647',
      font: '12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace',
      color: '#fff', background: 'rgba(20,16,38,0.92)', border: '1px solid #6c47ff',
      borderRadius: '8px', boxShadow: '0 4px 16px rgba(0,0,0,0.4)', maxWidth: '300px',
      backdropFilter: 'blur(2px)', userSelect: 'none',
    });

    const header = document.createElement('div');
    css(header, { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 8px', cursor: 'move', borderBottom: '1px solid rgba(108,71,255,0.4)' });
    header.title = 'Drag to move';

    const title = document.createElement('span');
    title.textContent = 'Claude HUD';
    css(title, { fontWeight: 'bold', color: '#cdbcff', marginRight: '8px' });

    const btns = document.createElement('span');
    const closeBtn = mkBtn('\u00d7', 'Hide (re-show with claudeHud2.show())', () => hide());
    css(closeBtn, { marginRight: '10px' });
    btns.appendChild(closeBtn);
    btns.appendChild(mkBtn('\ud83d\udcdd',
      'With Settings \u25b8 General open: fetch your preferences from GitHub and fill the Instructions box, then save',
      () => { setStatus('\u23f3 fetching preferences\u2026'); Promise.resolve(fillInstructions()).then(setStatus); }));
    btns.appendChild(mkBtn('\ud83c\udff7',
      'With Settings \u25b8 Billing open: read the plan name',
      () => setStatus(readPlan())));
    btns.appendChild(mkBtn('\ud83d\udccb',
      'Command shortcuts \u2014 fetch from GitHub, click one to insert it into the composer',
      () => { setStatus('\u23f3 loading commands\u2026'); Promise.resolve(toggleCommands()).then(setStatus); }));

    header.appendChild(title);
    header.appendChild(btns);

    hudStatus = document.createElement('div');
    css(hudStatus, { padding: '6px 8px', whiteSpace: 'normal', overflowWrap: 'anywhere',
      color: '#9a8cc8', fontSize: '11px', lineHeight: '1.35' });
    hudStatus.textContent = '\ud83d\udcdd prefs \u00b7 \ud83c\udff7 plan \u00b7 \ud83d\udccb commands';

    hudRoot.appendChild(header);
    hudRoot.appendChild(hudStatus);
    (document.body || document.documentElement).appendChild(hudRoot);
    makeDraggable(hudRoot, header);
  }

  // SPA hardening: if our node is detached from <body> on a client-side nav,
  // re-append it. We append directly to <body>, so a childList observer there
  // (no subtree) is enough and stays cheap.
  function keepAttached() {
    if (hudObserver) return;
    hudObserver = new MutationObserver(function () {
      if (hudRoot && document.body && !document.body.contains(hudRoot)) {
        document.body.appendChild(hudRoot);
      }
    });
    if (document.body) hudObserver.observe(document.body, { childList: true });
  }

  function show()    { ensureHud(); hudRoot.style.display = 'block'; keepAttached(); }
  function hide()    { if (hudRoot) hudRoot.style.display = 'none'; }
  function toggle()  { if (hudRoot && hudRoot.style.display !== 'none') hide(); else show(); }
  function destroy() {
    if (hudObserver) { hudObserver.disconnect(); hudObserver = null; }
    if (hudRoot && hudRoot.parentNode) hudRoot.parentNode.removeChild(hudRoot);
    hudRoot = null; hudStatus = null;
    window.__claudeHud2 = false;
  }
  // Note: isolated world → this object lives on the isolated window, not the page
  // console. The two buttons are the interface; these are for extension debugging.
  window.claudeHud2 = { show, hide, toggle, destroy, fillInstructions, readPlan,
                        toggleCommands, extractCommands,
                        reloadPrefs: () => { prefsCache = null; } };

  window.addEventListener('popstate', () => { try { show(); } catch (e) {} });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show);
  else show();
})();

JS_EOF
echo "  wrote claude_hud2.js"

# ─── package the unpacked folder into a .zip + .xpi via web-ext ──────────────
# Preflight already verified that web-ext is callable, so this is unconditional.
# `web-ext build` runs manifest validation — a clean build means the package
# is well-formed and ready for install.
ZIPDIR="web-ext-artifacts"
mkdir -p "$ZIPDIR"
echo "  packaging with web-ext (version $WEBEXT_VER)..."
if ! web-ext build --source-dir "$EXTDIR" --artifacts-dir "$ZIPDIR" --overwrite-dest >/dev/null; then
  echo "ERROR: 'web-ext build' failed. Check $EXTDIR/manifest.json for validation errors:" >&2
  echo "   web-ext lint --source-dir $EXTDIR" >&2
  exit 1
fi
ZIP="$(ls -t "$ZIPDIR"/*.zip 2>/dev/null | head -1 || true)"
if [ -z "$ZIP" ]; then
  echo "ERROR: web-ext build reported success but produced no .zip in $ZIPDIR" >&2
  exit 1
fi
# an .xpi is just the zip renamed; Firefox's "Install Add-on From File" wants .xpi
XPI="${ZIP%.zip}.xpi"
cp -f "$ZIP" "$XPI"
echo "  built package: $ZIP"
echo "  built package: $XPI  (identical bytes; .xpi is for Firefox file-install)"
echo ""

cat <<INSTR

Done. Build artifacts ready:
  Unpacked folder:  $EXTDIR/
    - manifest.json
    - claude_hud2.js
  Packaged (built by web-ext):
    - $ZIP
    - $XPI    (same bytes; Firefox's "Install Add-on From File" wants .xpi)

------------------------------------------------------------------------------
INSTALL — CHROME / EDGE / OPERA / BRAVE (Chromium 111+)
------------------------------------------------------------------------------
  1. Open the extensions page:
       Chrome: chrome://extensions    Edge:  edge://extensions
       Opera:  opera://extensions     Brave: brave://extensions
  2. Turn ON "Developer mode" (toggle, top-right of that page).
  3. Click "Load unpacked"  ->  select the  $EXTDIR/  folder.
  4. If asked, allow access to raw.githubusercontent.com — that is the
     preferences fetch behind the 📝 button.
  5. Open or refresh claude.ai — the "Claude HUD" panel appears top-right.
  Update after re-running this script: click the reload icon on the extension
  card, then hard-refresh claude.ai (Ctrl/Cmd+Shift+R).
  (Opera note: loading an UNPACKED extension needs no extra add-on; the
   "Install Chrome Extensions" add-on is only for the Chrome Web Store.)

------------------------------------------------------------------------------
INSTALL — FIREFOX: HOW LONG DOES IT LAST? (read first)
------------------------------------------------------------------------------
  Firefox extension lifetime depends entirely on the install path:
    Temporary add-on . . . . . . . until you close Firefox (wiped on restart/crash)
    Unsigned + pref off . . . . .  until you remove it; Nightly / Dev / ESR ONLY

  Quick picker:
    "Just poking for one session"           -> Temporary  (section below)
    "I'm on Nightly/Dev Edition, sticky"    -> PATH B     (unsigned + pref off)
    For signing / AMO distribution options: see browser_extension_signing.md

------------------------------------------------------------------------------
INSTALL — FIREFOX, TEMPORARY (Firefox 109+, wiped on restart)
------------------------------------------------------------------------------
  1. Open  about:debugging  ->  "This Firefox".
  2. "Load Temporary Add-on..."  ->  select  $EXTDIR/manifest.json.
  3. Refresh claude.ai. Removed when Firefox closes (fine for a quick look;
     NOT persistent).

------------------------------------------------------------------------------
INSTALL — FIREFOX, PERSISTENT (survives restarts, until you remove it)
------------------------------------------------------------------------------
  This script ALREADY built the package locally (above):
      $ZIP   and   $XPI
  Note: Release/Beta Firefox refuse unsigned add-ons for permanent install.
  For signing options (AMO self-distribution or listed): see browser_extension_signing.md

  PATH B - Disable signature enforcement  (Developer Edition / Nightly / ESR ONLY)
    In  about:config  set  xpinstall.signatures.required = false
        (stock Release/Beta IGNORE this pref - Dev/Nightly/ESR only)
    Then  about:addons  ->  gear  ->  "Install Add-on From File..."
    ->  pick the  $XPI  this script just built.
    Stays installed until you remove it.
    (An .xpi is just the .zip renamed; Firefox's file installer wants the .xpi name.)

------------------------------------------------------------------------------
VERIFY IT WORKS
------------------------------------------------------------------------------
  On claude.ai a purple "Claude HUD" panel appears top-right with three icons:
    📝  paste your prefs into Settings ▸ General "Instructions for Claude"
    🏷  read the plan name off Settings ▸ Billing
    📋  list command shortcuts — click one to insert it into the composer
  No panel? Check: extension enabled with no errors; you selected the folder
  CONTAINING manifest.json; browser new enough (Chromium 111+ / Firefox 109+);
  hard-refresh claude.ai.
INSTR
