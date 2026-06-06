#!/usr/bin/env bash
# ─── claude_browser_extension.sh ─────────────────────────────────────────────
#
# PURPOSE
#   Builds a local, unpacked Manifest V3 browser extension that auto-injects
#   claude_developer_debug.js into every claude.ai page. Unlike pasting the
#   script into the console, this runs automatically on each page load, so you
#   never re-paste after a refresh, and it patches fetch() *before* claude.ai's
#   own code runs — catching requests from the very first paint.
#
# WHAT THIS SCRIPT CREATES
#   claude-debug-extension/
#     manifest.json               — Manifest V3 manifest (Chrome / Firefox)
#     claude_developer_debug.js   — the debug monitor script
#
# ─── WHY THIS INJECTS INTO THE MAIN WORLD (read this) ─────────────────────────
#
#   The monitor works by replacing window.fetch with a wrapper. For that to
#   intercept claude.ai's traffic, the replacement must happen on the SAME
#   window object the page itself uses.
#
#   By default, extension content scripts run in an ISOLATED world: they share
#   the page's DOM but get their OWN copy of window and their OWN fetch. Setting
#   window.fetch there does NOT touch the page's fetch, so claude.ai's requests
#   sail past unmonitored — turnLog stays empty and _claudeDebug.histogram()
#   forever reports "not enough data". (Worse, _claudeDebug would live on the
#   isolated window, invisible to the page console where you'd type it.)
#
#   The fix is "world": "MAIN" in the content_scripts entry (see manifest below).
#   MAIN-world scripts execute in the page's own JavaScript context, so the
#   fetch patch lands on the real fetch and _claudeDebug is reachable straight
#   from the page console — exactly as if you'd pasted it in by hand, but
#   automatic and earlier (document_start, before claude.ai's bundle runs).
#
#   Trade-off: MAIN-world content scripts CANNOT use chrome.* extension APIs.
#   This monitor doesn't need any (it only touches window.fetch and console),
#   so that restriction costs us nothing here.
#
# HOW TO RUN
#   chmod +x claude_browser_extension.sh
#   ./claude_browser_extension.sh
#
# ─── INSTALLING IN CHROME (v111+) ─────────────────────────────────────────────
#
#   1. Open Chrome and go to:  chrome://extensions
#   2. Enable "Developer mode" (toggle, top-right corner)
#   3. Click "Load unpacked"
#   4. Select the claude-debug-extension/ folder this script just created
#   5. The extension appears in your list as "Claude Developer Debug"
#   6. Open (or refresh) claude.ai — the monitor is active automatically
#
#   To update after editing the JS:
#     - Edit claude-debug-extension/claude_developer_debug.js directly
#     - Go to chrome://extensions and click the ↺ reload icon on the card
#     - Refresh claude.ai
#
#   Disable without uninstalling:  toggle the extension off on chrome://extensions
#   Uninstall:                     click "Remove" on chrome://extensions
#
# ─── INSTALLING IN FIREFOX (v128+) ────────────────────────────────────────────
#
#   NOTE: "world": "MAIN" for content scripts requires Firefox 128 or newer.
#   On older Firefox the script still loads but runs in the ISOLATED world and
#   will NOT intercept fetch (the failure mode described above).
#
#   Temporary install (lasts until Firefox restarts):
#   1. Open Firefox and go to:  about:debugging
#   2. Click "This Firefox" in the left sidebar
#   3. Click "Load Temporary Add-on..."
#   4. Navigate into claude-debug-extension/ and select manifest.json
#
#   Permanent install (Firefox won't keep unpacked MV3 add-ons without signing):
#     npm install -g web-ext
#     cd claude-debug-extension
#     web-ext build          # produces a .zip you can self-sign / sideload
#
# ─── VERIFYING IT WORKS ───────────────────────────────────────────────────────
#
#   1. Open claude.ai
#   2. Open DevTools (F12 / Cmd+Option+I) → Console tab
#   3. The purple "Claude Developer Debug Monitor active" banner should appear
#      automatically, with nothing pasted
#   4. Send a message — you'll see [REQ], [RES], [SSE], [PERF] log lines
#   5. After 2+ completed turns, try:  _claudeDebug.histogram()
#
#   If the banner does NOT appear:
#     - chrome://extensions — is the extension enabled and showing no errors?
#     - Did you load the folder that CONTAINS manifest.json (not a parent)?
#     - Is the browser new enough for "world": "MAIN" (Chrome 111+ / FF 128+)?
#     - Hard-refresh claude.ai: Cmd+Shift+R / Ctrl+Shift+R
#
# ─── LIVE EXPRESSION VIEWS (the 👁 button) ────────────────────────────────────
#
#   DevTools has two input spots, and mixing them up causes runaway console
#   scrolling:
#     - The  >  prompt at the BOTTOM of the Console runs an expression ONCE per
#       Enter. Use this for the helpers below that print (they end in "()").
#     - The 👁 "Create live expression" button pins an expression at the TOP of
#       the Console and RE-EVALUATES it ~4x/second, rendering its return value
#       in place (it overwrites, never appends to the log).
#
#   Because a Live Expression re-runs continuously, NEVER put a printing helper
#   in it. Helpers like _claudeDebug.turns(), .histogram(), .stats(), .pending()
#   call console.table/console.log; in a Live Expression those side effects fire
#   on every tick and flood the log forever. Run those from the bottom prompt.
#
#   Safe to put in a Live Expression (they RETURN a value, never log) — type
#   them WITHOUT parentheses:
#     _claudeDebug.summary   — compact rolling object that updates in place:
#                              { turns, inFlight, lastTotalMs, medianTotalMs,
#                                p90TotalMs, medianTTFTMs }
#     _claudeDebug.data      — snapshot array of every recorded turn (expandable)
#     pendingRequests.size   — (if you want a bare number) in-flight count
#
#   To create one: click 👁, type e.g.  _claudeDebug.summary , press Enter. It
#   sits at the top and ticks over as new turns land, with zero console spam.
#   To remove one (and stop any existing scroll): click the × next to it in the
#   pinned strip, or just refresh the page — the extension re-injects on load.
#
#   Prefer a readable printed snapshot? Run  _claudeDebug.report()  once from the
#   > prompt: it logs the summary one field per line, then draws the histogram.
#   (It prints, so keep it on the prompt — not in a Live Expression.)
#
# ─── COMPATIBILITY / FALLBACK FOR OLDER BROWSERS ──────────────────────────────
#
#   "world": "MAIN" is the simplest reliable way to reach the page context, but
#   it needs Chrome/Edge 111+ or Firefox 128+. On older browsers the classic
#   alternative is to keep an ISOLATED-world content script that injects a
#   <script src> tag pointing at the monitor (listed under web_accessible_
#   resources); the injected tag then runs in the MAIN world. That needs a
#   second loader file plus a web_accessible_resources block, so it is omitted
#   here in favor of the one-line "world": "MAIN" approach you asked for.
#
# ─── PRIVACY NOTE ─────────────────────────────────────────────────────────────
#
#   The extension runs ONLY on claude.ai (declared in manifest "matches").
#   Everything stays in your browser — nothing is sent anywhere. The fetch
#   interception is read-only: the response body is cloned with .tee() and the
#   original is handed back to claude.ai untouched. No persistence beyond the
#   page's lifetime — turn data lives in memory and clears on refresh.
#
# ─── PUBLIC RELEASE NOTES (for future reference) ─────────────────────────────
#
#   If you ever want to publish to the Chrome Web Store or Firefox AMO:
#     Chrome Web Store: one-time $5 developer fee; review takes days–weeks;
#       reviewers scrutinize fetch() interception, so expect to supply a privacy
#       policy stating no data leaves the browser.
#       https://chrome.google.com/webstore/devconsole
#     Firefox AMO: free; faster review (~1–3 days for listed add-ons); same
#       privacy-policy requirement for network-intercepting add-ons.
#       https://addons.mozilla.org/developers/
#   For technical users, shipping the .js with "paste in console" instructions
#   has zero friction and no review. A store release only makes sense for broad
#   non-technical reach.
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

EXTDIR="claude-debug-extension"

echo "Creating extension folder: $EXTDIR/"
mkdir -p "$EXTDIR"

# ─── manifest.json ────────────────────────────────────────────────────────────
# Manifest V3 (required by Chrome; also read by Firefox 109+).
#   content_scripts          — auto-injects the monitor into every claude.ai page.
#   "world": "MAIN"          — runs the script in the PAGE's JS context, not the
#                              isolated extension context, so window.fetch is the
#                              real one and _claudeDebug is reachable from the page
#                              console. THIS LINE is what makes the monitor work;
#                              without it the patch hits an isolated fetch and
#                              intercepts nothing. (Chrome 111+, Firefox 128+.)
#   "run_at": document_start — patch fetch BEFORE claude.ai's bundle loads, so
#                              no early requests are missed.
#   "matches"                — restricts the extension to claude.ai only.

cat > "$EXTDIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Claude Developer Debug",
  "version": "1.7",
  "description": "Injects the Claude network/performance debug monitor into claude.ai's page context (MAIN world). Logs all API requests, SSE streams, turn latency, and TTFT to the DevTools console.",
  "content_scripts": [
    {
      "matches": ["https://claude.ai/*"],
      "js": ["claude_developer_debug.js"],
      "run_at": "document_start",
      "world": "MAIN"
    }
  ]
}
EOF

echo "  wrote manifest.json"

# ─── claude_developer_debug.js ────────────────────────────────────────────────
# The full debug monitor. Quoted heredoc (no variable expansion inside).
# Injected into the MAIN world by the manifest above, so its window.fetch patch
# applies to the real page fetch rather than an isolated copy.

cat > "$EXTDIR/claude_developer_debug.js" << 'EOF'
// ─── Claude Developer Debug Monitor ──────────────────────────────────────────
//
// PURPOSE
//   Intercepts fetch() (and now WebSocket) traffic claude.ai makes to its own
//   (and Anthropic's) endpoints, logging requests, responses, errors, streaming
//   state, performance, transfer sizes, and HEURISTIC token/throughput estimates
//   to the DevTools console. Use it to diagnose hangs/stalls and to estimate
//   your own usage rates — entirely client-side, with NO API key.
//
// HOW TO USE
//   PRIMARY — load as the claude-debug-extension built by claude_browser_extension.sh
//   (MAIN world, document_start: auto-starts, survives refresh, catches the first
//   request). FALLBACK — paste this whole file into the claude.ai DevTools console
//   (does not persist; only sees requests made after paste).
//
//   WHY THE MAIN WORLD MATTERS
//   The monitor replaces window.fetch. An ISOLATED-world content script gets its
//   own window/fetch and would never see the page's real traffic; MAIN world (and
//   the console) run in the page context, so both actually intercept. Because the
//   code runs in the page realm, claude.ai's CSP applies: no eval / new Function /
//   string setTimeout|setInterval. All timers here use function callbacks.
//
// CONSOLE HELPERS (call with parens)
//   _claudeDebug.pending()   — table of in-flight requests
//   _claudeDebug.count()     — how many in flight
//   _claudeDebug.stats()     — min/median/p90/max for TTFT / stream / total
//   _claudeDebug.histogram(metric?, buckets?)  — ASCII histogram. metric ∈
//       total | ttft | ttftEvent | streamDuration | estOutputTokens |
//       tokPerSec | estInputTokens | reqBytes | streamBytes   (default total, 5)
//   _claudeDebug.turns()     — table of every completed turn
//   _claudeDebug.rates()     — rolling messages/tokens/bytes over 1m/5m/1h/24h
//   _claudeDebug.byConversation() — per-conversation totals
//   _claudeDebug.endpoints()     — per-endpoint request tally (all monitored /api/ calls)
//   _claudeDebug.sockets()   — WebSocket activity summary
//   _claudeDebug.report()    — readable summary + rates + histogram
//   _claudeDebug.reset()     — clear turn log
//   _claudeDebug.export()    — copy all turn data as JSON to clipboard
//   _claudeDebug.stop()      — restore fetch + WebSocket and detach everything
//
//   Value getters (NO parens) — safe inside a DevTools Live Expression:
//   _claudeDebug.data        — snapshot array of all recorded turns
//   _claudeDebug.summary     — compact rolling object (counts, medians, est tokens, rates)
//
// LOG PREFIXES
//   [REQ] sent (method, URL, request bytes, ~input tokens) · [RES] response
//   (status, elapsed, all headers, server-timing) · [FAIL] fetch threw ·
//   [HANG] pending past the heartbeat · [SSE] stream lifecycle (events, ~output
//   tokens, ~tokens/sec) · [SSE STALL] stream idle · [SLOW] turn above session p90 ·
//   [PERF] turn summary · [TIMING] resource timing (dns/tls/ttfb + transfer size +
//   protocol) · [WS] WebSocket open/close · [TAB]/[NET] browser events
//
// TURN TIMING MODEL (performance.now(), monotonic)
//   t0 send · t1 first network chunk · t2 stream close.
//   TTFT = t1 - t0 (first NETWORK chunk). TTFT(event) = first decoded SSE event.
//   Streaming = t2 - t1. Total = t2 - t0.
//
// TOKEN ESTIMATES — READ THIS
//   claude.ai does NOT expose token counts, and the current model tokenizer is not
//   public, so every "token" number here is a HEURISTIC ESTIMATE (≈ chars / 3.6, or exact from the stream’s usage object when present) and
//   is marked with "~". It is good enough to estimate USAGE RATES and trends, not
//   to bill against. Input is estimated from the request body's string content;
//   output from the decoded SSE event payloads. For EXACT counts use the separate
//   _claudeTokens tool / the count_tokens API with your own key — intentionally not
//   done here so the monitor needs no key. Prompt/response CONTENT is parsed locally
//   for sizing only and is never logged.
//
// LIMITATIONS
//   - Intercepts fetch() and WebSocket; XMLHttpRequest / EventSource are not logged.
//   - Scope: claude.ai + anthropic.com (same/sub-domain), fetch path under /api/.
//   - Token/throughput figures are estimates (see above); they measure consumption,
//     not remaining plan headroom (only the app's own indicators show headroom).
//   - Built on claude.ai's UNDOCUMENTED internal request/SSE shapes; a product
//     change can alter the body/event format and degrade the estimates without
//     notice. Latency/size metrics are schema-independent and keep working.
//   - Streams are read via response.clone(); the page gets the original Response
//     untouched. A clone buffers the unread remainder if the two readers diverge;
//     a watchdog releases the monitor's branch after a long idle.
//   - In-memory only; resets on refresh; capped at MAX_TURNS most-recent turns.
// ─────────────────────────────────────────────────────────────────────────────

(() => {
  'use strict';

  // Idempotence guard: never wrap fetch/WebSocket twice.
  if (window.__claudeDebugMonitor) {
    console.warn('Claude Developer Debug Monitor already active — skipping re-install.');
    return;
  }
  window.__claudeDebugMonitor = true;

  // ─── Tunables (all integers; ms unless noted) ──────────────────────────────
  const HANG_INTERVAL_MS   = 5000;   // check cadence while a request has no response yet
  const HANG_WARN_MS       = 10000;  // warn once a request exceeds this with no response
  const HANG_SLOW_WARN_MS  = 20000;  // higher bar for slow-by-nature endpoints (completion / upload)
  const STALL_CHECK_MS     = 5000;   // watchdog tick while a stream is open
  const STREAM_STALL_MS    = 15000;  // warn if a stream is idle this long mid-flight
  const STREAM_MAX_IDLE_MS = 90000;  // release the monitor's reader after this idle
  const MAX_TURNS          = 1000;   // cap on retained turn records
  const MAX_SOCKETS        = 200;    // cap on retained WebSocket records
  const BAR_WIDTH          = 30;     // max histogram bar width, in chars
  const STACK_CALLER_FRAMES = 3;     // how many caller frames to attribute a fetch
  const EST_CHARS_PER_TOKEN = 3.6;   // rough heuristic for English prose (NOT exact)
  const SCHEMA_VERSION     = 2;      // hud_audit snapshot schema (bump when fields change)
  const SLOW_MIN_SAMPLES   = 10;     // need this many turns before flagging [SLOW]
  const HUD_REFRESH_MS     = 1000;   // on-page overlay refresh cadence
  const QUOTA_POLL_MS      = 60000;  // while the HUD is open+visible, refresh exact /usage at most this often
  const BODY_SCAN_MAX      = 524288; // bodies larger than this (chars) skip the per-leaf walk
  const SLOW_P90_REFRESH   = 25;     // recompute the [SLOW] p90 baseline every N turns, not every turn
  const ASSESS = {                   // session-relative assessment thresholds (tune freely)
    slowVsMedian: 1.5,   // a turn is "slow" past this x median total (and above p90)
    ttftSpike:    2,     // TTFT p90 past this x median => spiky
    inOutRatio:   20,    // input:output past this => context-heavy
    ctxGrowth:    4,     // input grew past this x oldest retained turn => bloat
    cacheHitLow:  0.3,   // cache hit below this => low reuse
    tpsDip:       0.5,   // tok/s below this x median => throughput dip
  };

  // Hosts we care about (exact host or any subdomain).
  const API_HOSTS = ['claude.ai', 'anthropic.com'];

  // ─── State ──────────────────────────────────────────────────────────────────
  const origFetch = window.fetch;
  const origWebSocket = window.WebSocket;
  const origXHR = window.XMLHttpRequest;
  const pendingRequests = new Map();
  const turnLog = [];   // see record shape in recordTurn()
  const wsLog = [];     // { url, opened, closed, sent, recv }
  let reqCounter = 0;
  let completionCounter = 0;   // session count of FRESH completion turns (retries excluded; the "message #" the probe reports alongside the absolute request id)
  const endpointCounts = new Map();   // normalized endpoint key -> count, over every monitored request (see endpointKey / endpoints())
  const encoder = new TextEncoder();

  // Health / capacity tracking (keyless, exact).
  let maxInFlight = 0;                 // peak concurrent monitored requests
  let failCount = 0;                   // fetch() rejections
  let streamErrorCount = 0;            // SSE "error" events (claude.ai returns these with HTTP 200)
  const statusCounts = new Map();      // HTTP status -> count
  let lastRateLimit = null;            // latest anthropic-ratelimit-* / retry-after snapshot
  let orgId = null;                    // organization id seen in any monitored URL — enables refreshQuota()
  let probeArmed = false;              // schema-probe: analyze the next monitored SSE turn
  let captureCallers = false;          // capture a JS stack per request (off by default; priciest per-request op)
  let slowP90 = null, slowP90At = 0;   // cached [SLOW] baseline + the turn count it was computed at
  const COMPLETION_RE    = /\/(retry_)?completion\b/i;            // a chat-completion stream (.../chat_conversations/<id>/completion)
  const RETRY_RE         = /\/retry_completion\b/i;               // a regenerated answer — does NOT consume a fresh message slot the way a new turn does
  const SLOW_ENDPOINT_RE = /\/(retry_)?completion\b|upload-file\b/i; // slow by nature: stream TTFT or a file upload
  // Endpoints the web app hits to render its own usage UI — best-effort, no-key
  // source of plan tier + exact rolling-window quota (response JSON is scanned for
  // tier/limit fields; content is never logged).
  const USAGE_RE         = /(usage|message_limit|rate_limit|\/limits|subscription|bootstrap|statsig|\/account\b)/i;
  const DELTA_META_KEYS  = ['type', 'index', 'stop_reason', 'stop_sequence', 'stop_details', 'message', 'display_content']; // non-content delta fields

  // Time tracking. SESSION = since the monitor loaded (page open, incl. idle);
  // CHAT = first turn -> last turn span; ENGAGED = summed turn durations (generating).
  const SESSION_START = Date.now();
  let firstTurnTs = null, lastTurnTs = null, engagedMs = 0;

  // Per-load nonce. reqCounter (and thus turn `id`) restarts at 1 every page load,
  // so `id` alone is NOT unique across reloads/pastes; snapshots carry this nonce
  // and a composite rowKey (`nonce:id`) so a ledger can dedup turns correctly.
  const SESSION_NONCE = `${SESSION_START.toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

  // ── localStorage + time-series helpers ──────────────────────────────────────
  // One place for the "swallow errors" persistence policy and the shared
  // push/trim logic the usage- and pace-histories both use.
  const lsGet = (key, fb) => { try { const j = localStorage.getItem(key); return j ? (JSON.parse(j) ?? fb) : fb; } catch (e) { return fb; } };
  const lsSet = (key, val) => { try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {} };
  // Trim every array in a { key: [{ ts, … }] } store to entries newer than maxMs.
  function trimStore(store, maxMs) {
    const now = Date.now();
    for (const k of Object.keys(store)) {
      const a = store[k];
      store[k] = Array.isArray(a) ? a.filter(x => x && now - x.ts < maxMs) : [];
    }
    return store;
  }
  // Append a { ts, … } point to store[key] (creating the array), pushing only when
  // shouldPush(last, point) is true, then trim to maxMs and persist under lsKey.
  function pushSample(store, lsKey, key, point, maxMs, shouldPush) {
    const arr = store[key] || (store[key] = []);
    const last = arr[arr.length - 1];
    if (!last || shouldPush(last, point)) arr.push(point);
    const cutoff = point.ts - maxMs;
    while (arr.length > 1 && arr[0].ts < cutoff) arr.shift();
    lsSet(lsKey, store);
  }

  // Subscription state (no API key needed). Plan tier + rolling-window quota are
  // the metrics a Free/Pro/Max account is actually metered on. Both persist across
  // reloads via localStorage so a single snapshot can reflect the true window.
  let detectedPlan = null;
  try { detectedPlan = localStorage.getItem('claudeDebugPlan') || null; } catch (e) {}   // raw string, not JSON
  // window-name -> { usedPct, status, resetsAt, capturedAt }; drop windows already past reset.
  let quotaWindows = lsGet('claudeDebugQuota', {});
  { const _now = Date.now();
    for (const k of Object.keys(quotaWindows)) { const w = quotaWindows[k]; if (w && Number.isFinite(w.resetsAt) && w.resetsAt < _now) delete quotaWindows[k]; } }

  // Short history of usedPct readings per window (for burn-rate / minutes-to-cap).
  let usageHistory = trimStore(lsGet('claudeDebugUsageHist', {}), 3600000);   // drop readings >1h on load

  // Pace time-series per window (for the tachometer graph): one { ts, mult } point
  // appended each /usage poll once a pace is computable, retained PACE_LOG_MS.
  const PACE_LOG_MS = 5 * 60 * 60 * 1000;   // keep ~5h of pace points
  let paceLog = trimStore(lsGet('claudeDebugPaceLog', {}), PACE_LOG_MS);
  function recordPaceSample(name, mult) {
    if (typeof mult !== 'number' || !Number.isFinite(mult)) return;
    pushSample(paceLog, 'claudeDebugPaceLog', name, { ts: Date.now(), mult }, PACE_LOG_MS,
      (last, p) => p.ts - last.ts > 5000);   // skip rapid dupes
  }

  // On-page overlay (HUD) state
  let hudRoot = null, hudTitle = null, hudBody = null, hudFoot = null, hudInterval = null, hudCollapsed = true;
  let lastQuotaPollAt = 0;              // throttle for the HUD's background /usage refresh
  let hudPos = null;                   // {left, top} drag position (persisted best-effort)
  // Metrics the HUD 📊 button cycles through on repeated clicks.
  const HUD_HIST_METRICS = ['total', 'ttft', 'ttftEvent', 'streamDuration',
    'outputTokens', 'inputTokens', 'tokPerSec', 'interEventP95', 'reqBytes', 'streamBytes'];
  let hudHistIdx = 0;
  // Second overlay panel that renders the histogram as DOM on click (no auto-refresh).
  let histRoot = null, histTitle = null, histBody = null;
  // Tachometer panel: SVG pace-vs-time graph; auto-refreshes while open.
  let paceRoot = null, paceTitle = null, paceBody = null;

  // ─── Small helpers ──────────────────────────────────────────────────────────
  const fmtMs = v =>
    v == null ? 'n/a' : v < 1000 ? `${Math.round(v)}ms` : `${(v / 1000).toFixed(2)}s`;

  const fmtDur = ms => {
    if (ms == null) return 'n/a';
    const s = Math.round(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return h ? `${h}h ${m}m` : m ? `${m}m ${sec}s` : `${sec}s`;
  };

  // Parse a claude.ai message_limit payload into a usable shape. Real schema (confirmed):
  // { type, representativeClaim, overageInUse, overageDisabledReason,
  //   windows: { '5h': {status, resets_at (unix SECONDS), utilization 0..1}, '7d': {...} } }.
  // The flat remaining/resetsAt fields are usually null — `windows` is the source of truth.
  function quotaSummary(lim) {
    if (!lim || typeof lim !== 'object') return null;
    const ml = lim.windows ? lim : (lim.message_limit && typeof lim.message_limit === 'object' ? lim.message_limit : lim);
    const q = { type: ml.type || null, rep: ml.representativeClaim || null,
                overageInUse: !!ml.overageInUse, overageDisabledReason: ml.overageDisabledReason || null, windows: [] };
    const W = ml.windows;
    if (W && typeof W === 'object') {
      for (const k in W) {
        const w = W[k]; if (!w || typeof w !== 'object') continue;
        const util = Number.isFinite(w.utilization) ? w.utilization : null;
        q.windows.push({ name: k, status: w.status || null,
          util: util,                                          // raw 0..1 float (null if absent); used by windowPace()
          usedPct: util != null ? Math.round(util * 100) : null,
          resetsInMs: Number.isFinite(w.resets_at) ? w.resets_at * 1000 - Date.now() : null });
      }
    } else if (ml.remaining != null) {                       // legacy flat shape
      q.windows.push({ name: 'limit', leftN: ml.remaining, status: ml.type || null,
        resetsInMs: Number.isFinite(ml.resetsAt) ? ml.resetsAt - Date.now() : null });
    }
    return (q.windows.length || q.type) ? q : null;
  }
  function fmtQuotaWindow(w) {   // value only, e.g. "80% left (resets 2h 13m)"; caller adds the window name
    const head = w.usedPct != null ? `${100 - w.usedPct}% left` : (w.leftN != null ? `${w.leftN} left` : (w.status || '?'));
    const rs = (w.resetsInMs != null && w.resetsInMs > 0) ? ` (resets ${fmtDur(w.resetsInMs)})` : '';
    return `${head}${rs}`;
  }
  function fmtQuotaLine(q) {      // single-line form for console/log; the HUD wraps per-window instead
    if (!q) return null;
    const parts = q.windows.map(w => `${w.name} ${fmtQuotaWindow(w)}`);
    let s = parts.join(' · ') || (q.type || '');
    if (q.overageInUse) s += ' · OVERAGE ON';
    else if (q.overageDisabledReason) s += ` · overage off (${q.overageDisabledReason})`;
    return s;
  }
  function latestQuota() {   // most recent turn carrying a limit (error turns have none)
    for (let i = turnLog.length - 1; i >= 0; i--) { const q = quotaSummary(turnLog[i].messageLimit); if (q) return q; }
    return null;
  }

  // Persist each rolling window's utilisation so a snapshot reflects the real
  // subscription window even across page reloads. Keyed by window name; we keep
  // the freshest reading per reset epoch.
  function persistQuota(messageLimit) {
    const q = quotaSummary(messageLimit);
    if (!q || !q.windows || !q.windows.length) return;
    const now = Date.now();
    for (const w of q.windows) {
      if (!w.name) continue;
      const resetsAt = Number.isFinite(w.resetsInMs) ? now + w.resetsInMs : null;
      quotaWindows[w.name] = { usedPct: (w.usedPct != null ? w.usedPct : null), status: w.status || null, resetsAt, capturedAt: now };
    }
    lsSet('claudeDebugQuota', quotaWindows);
  }

  // The /api/organizations/<id>/usage payload is a DIFFERENT shape from the SSE
  // message_limit: a flat map of window-name -> { utilization (0..100 PERCENT),
  // resets_at (ISO string) }, plus an extra_usage (overage) block. Many windows
  // are null when not active for the plan. We accept any value that looks like a
  // window so new server-side windows are captured without a code change.
  const USAGE_WINDOW_ALIAS = { five_hour: '5h', seven_day: '7d', seven_day_opus: '7d_opus',
    seven_day_sonnet: '7d_sonnet', seven_day_cowork: '7d_cowork', seven_day_oauth_apps: '7d_oauth' };
  function noteUsageEndpoint(j) {
    if (!j || typeof j !== 'object') return false;
    const now = Date.now();
    let hit = false;
    for (const k in j) {
      const w = j[k];
      if (!w || typeof w !== 'object') continue;
      if (typeof w.utilization !== 'number' || w.resets_at == null) continue;   // skip nulls / non-windows
      const resetsAt = Date.parse(w.resets_at);
      const name = USAGE_WINDOW_ALIAS[k] || k;
      quotaWindows[name] = { usedPct: Math.round(w.utilization), status: null,   // endpoint already reports 0..100
        resetsAt: Number.isFinite(resetsAt) ? resetsAt : null, capturedAt: now };
      recordUsageSample(name, Math.round(w.utilization));   // feed the burn-rate history
      hit = true;
    }
    const ex = j.extra_usage;   // overage / pay-as-you-go credits
    if (ex && typeof ex === 'object' && ex.is_enabled && typeof ex.utilization === 'number') {
      quotaWindows['extra'] = { usedPct: Math.round(ex.utilization), status: 'overage', resetsAt: null, capturedAt: now };
      hit = true;
    }
    // Now that this poll's usedPct samples are recorded, compute the 5h pace and log
    // it as a tachometer point (null early on, when there is no baseline yet).
    if (hit) { const pp = usagePace('5h'); if (pp && pp.multiplier != null) recordPaceSample('5h', pp.multiplier); }
    if (hit) lsSet('claudeDebugQuota', quotaWindows);
    return hit;
  }

  // Silent fetch of the exact usage endpoint (no console output). Rides the page's
  // session cookies; origFetch so it isn't re-instrumented. Returns the JSON or null.
  async function fetchUsage() {
    if (!orgId) return null;
    try {
      const r = await origFetch(`/api/organizations/${orgId}/usage`, { method: 'GET', credentials: 'same-origin', headers: { 'content-type': 'application/json' } });
      if (!r.ok) return null;
      const j = await r.json();
      noteUsageEndpoint(j);
      return j;
    } catch { return null; }
  }
  // Flatten the persisted windows into a snapshot array (resets recomputed to "ms from now").
  function quotaWindowsSnapshot() {
    const out = [];
    for (const k in quotaWindows) {
      const w = quotaWindows[k];
      const p = usagePace(k);
      out.push({ window: k, usedPct: w.usedPct ?? null, status: w.status || null,
        resetsInMs: Number.isFinite(w.resetsAt) ? w.resetsAt - Date.now() : null, capturedAt: w.capturedAt || null,
        paceMultiplier: p && p.multiplier != null ? +p.multiplier.toFixed(2) : null,
        estMinsLeft: p ? p.estMinsLeft : null });
    }
    return out;
  }

  // Best-effort, no-key plan detection from a usage/account response the web app
  // already fetched. Scans common tier fields; never logs content. Latches once.
  const PLAN_RE = /\b(free|pro|max|team|enterprise)\b/i;
  function notePlanFromJson(obj) {
    if (detectedPlan || !obj || typeof obj !== 'object') return;
    const cand = obj.subscription || obj.plan || obj.tier || obj.rate_limit_tier ||
      (obj.account && (obj.account.subscription || obj.account.plan || obj.account.tier)) ||
      (obj.organization && (obj.organization.billing_type || obj.organization.rate_limit_tier));
    let s = null;
    if (typeof cand === 'string') s = cand;
    else if (cand && typeof cand === 'object') s = cand.tier || cand.name || cand.plan || null;
    if (typeof s !== 'string') return;
    const m = s.match(PLAN_RE);
    if (m) { detectedPlan = m[1].toLowerCase(); try { localStorage.setItem('claudeDebugPlan', detectedPlan); } catch (e) {} }
  }

  // Pull a message_limit-shaped object out of a usage payload (top level or one deep).
  function findMessageLimit(j) {
    if (!j || typeof j !== 'object') return null;
    if (j.message_limit || j.windows) return j;
    for (const k in j) { const v = j[k]; if (v && typeof v === 'object' && (v.message_limit || v.windows)) return v; }
    return null;
  }

  // Heuristic cross-check: count rendered assistant turns in the DOM. If this
  // diverges from the completion count, traffic is escaping the fetch/XHR patches
  // (e.g. a Web Worker or service worker). Selectors are best-effort and may drift.
  function domTurnCount() {
    try {
      const sel = document.querySelectorAll('[data-testid="assistant-turn"], div.font-claude-message, [data-is-streaming]');
      return sel ? sel.length : null;
    } catch { return null; }
  }

  // Stop-reason tally across retained turns (quick drift signal for the ledger).
  function stopReasonDistribution() {
    const out = {};
    for (const t of turnLog) { const k = t.stopReason || 'none'; out[k] = (out[k] || 0) + 1; }
    return out;
  }

  // --- usage-window pace ------------------------------------------------------
  // How fast is a rolling usage window's utilization moving, relative to the
  // clock?  Over the window's own length the bar would travel 0->100% if you
  // consumed evenly, so "time-implied" change over `elapsedMin` is
  // elapsedMin / windowMin of the full budget.  The multiplier is the actual
  // utilisation change divided by that:
  //     multiplier = ΔutilFraction * windowMin / elapsedMin
  //   = 1.0  -> burning exactly at the pace that hits 100% at window end
  //   > 1.0  -> faster than the clock (utilisation climbing quicker)
  //   < 1.0  -> slower; 0 -> flat; negative -> utilisation falling (recovering,
  //             as old usage ages out of the rolling window).
  const PACE_LOOKBACK_MS = 10 * 60 * 1000;   // "last 10 minutes"

  function windowMinutes(name) {             // '5h'->300, '7d'->10080, '30m'->30
    const m = /^(\d+)\s*([mhd])$/.exec(name || '');
    if (!m) return null;
    const n = +m[1];
    return m[2] === 'm' ? n : m[2] === 'h' ? n * 60 : n * 1440;
  }
  function windowUtilAt(i, name) {           // raw utilisation (0..1) for `name` in turnLog[i], or null
    const q = quotaSummary(turnLog[i].messageLimit);
    if (!q) return null;
    const w = q.windows.find(x => x.name === name);
    return w && w.util != null ? w.util : null;
  }
  // Shared pace-selection used by both windowPace (turnLog utilisation) and
  // usagePace (/usage history). Given samples ascending by ts, return the newest
  // point (b) and the oldest within lookback (a; fallback: the first point just
  // past the cutoff), plus the real elapsed span in minutes. null if <2 / no span.
  function pickSpan(samples, lookbackMs) {
    if (!Array.isArray(samples) || samples.length < 2) return null;
    const b = samples[samples.length - 1];
    const cutoff = b.ts - lookbackMs;
    let a = null;
    for (let i = samples.length - 2; i >= 0; i--) {
      if (samples[i].ts >= cutoff) a = samples[i];      // keep walking back to the oldest in-window
      else { if (!a) a = samples[i]; break; }           // first sample past the cutoff (fallback only)
    }
    if (!a) return null;
    const elapsedMin = (b.ts - a.ts) / 60000;
    return elapsedMin > 0 ? { a, b, elapsedMin } : null;
  }
  function windowPace(name, lookbackMs = PACE_LOOKBACK_MS) {
    const winMin = windowMinutes(name);
    if (!winMin) return null;
    // {ts, util} for every turn that carries this window's utilisation
    const samples = [];
    for (let i = 0; i < turnLog.length; i++) {
      const u = windowUtilAt(i, name);
      if (u != null) samples.push({ ts: turnLog[i].ts, util: u });
    }
    const span = pickSpan(samples, lookbackMs);
    if (!span) return null;
    const deltaUtil = span.b.util - span.a.util;        // signed fraction
    const timeImplied = span.elapsedMin / winMin;        // fraction of budget time alone accounts for
    if (timeImplied <= 0) return null;
    return { multiplier: deltaUtil / timeImplied, deltaPP: deltaUtil * 100, elapsedMin: span.elapsedMin };
  }
  function fmtPace(p) {                                  // "1.42x time (+4.7pp / 9.8m)"
    const sign = p.deltaPP >= 0 ? '+' : '';
    return `${p.multiplier.toFixed(2)}x time (${sign}${p.deltaPP.toFixed(1)}pp / ${p.elapsedMin.toFixed(1)}m)`;
  }

  // ── Exact /usage burn-rate (pace) + minutes-to-cap ──────────────────────────
  // The /usage endpoint reports usedPct (0..100), not the SSE 0..1 utilisation, and
  // it isn't tied to turnLog — so it needs its own little time series. We keep a
  // short, persisted history of readings per window and extrapolate from it.
  const USAGE_HISTORY_MS = 15 * 60 * 1000;   // retain ~15 min of readings
  function recordUsageSample(name, used) {
    if (typeof used !== 'number') return;
    pushSample(usageHistory, 'claudeDebugUsageHist', name, { ts: Date.now(), used }, USAGE_HISTORY_MS + 60000,
      (last, p) => last.used !== p.used || p.ts - last.ts > 20000);   // skip identical spam; keep a fallback baseline
  }
  // Pace + estMinsLeft for a /usage window. multiplier matches windowPace() (1.0 =
  // on track to hit the cap exactly at reset). estMinsLeft = minutes until usedPct
  // reaches 100 at the current NET rate (the delta already nets out aging-out), or
  // null when flat/recovering or no baseline yet.
  function usagePace(name, lookbackMs = PACE_LOOKBACK_MS) {
    const winMin = windowMinutes(name);
    const span = pickSpan(usageHistory[name], lookbackMs);
    if (!winMin || !span) return null;
    const now = span.b, then = span.a, elapsedMin = span.elapsedMin;
    const deltaPP = now.used - then.used;                // percentage points (signed)
    const burnPerMin = deltaPP / elapsedMin;             // pp/min (signed)
    const timeImplied = elapsedMin / winMin;
    const multiplier = timeImplied > 0 ? (deltaPP / 100) / timeImplied : null;
    const remaining = 100 - now.used;
    // Raw projection: minutes for usedPct to reach 100 at the current net burn rate.
    // null when flat/recovering (burnPerMin <= 0) — the cap is never reached.
    const minsToCap = burnPerMin > 0 ? Math.round(remaining / burnPerMin) : null;
    // The window frees its quota at reset, so usable runway can never exceed the time
    // left until reset. Use the EXACT /usage resetsAt (no-key endpoint, set by
    // noteUsageEndpoint) as the "time left" source, and clamp:
    //   pace > 1  -> cap arrives before reset -> estMinsLeft = minsToCap   (< minsToReset)
    //   pace == 1 -> cap coincides with reset  -> estMinsLeft = minsToReset
    //   pace < 1 / flat / recovering           -> reset arrives first      -> estMinsLeft = minsToReset
    const qw = quotaWindows[name];
    const minsToReset = (qw && Number.isFinite(qw.resetsAt))
      ? Math.max(0, Math.round((qw.resetsAt - Date.now()) / 60000)) : null;
    let estMinsLeft = minsToCap;
    if (minsToReset != null) estMinsLeft = (minsToCap == null) ? minsToReset : Math.min(minsToCap, minsToReset);
    // Which event binds (true = cap reached before reset, i.e. pace > 1).
    const capBinds = (minsToCap != null && minsToReset != null) ? (minsToCap < minsToReset) : (minsToCap != null);
    return { multiplier, deltaPP, elapsedMin, burnPerMin, minsToCap, minsToReset, estMinsLeft, capBinds, used: now.used };
  }

  const fmtBytes = b =>
    b == null ? 'n/a'
      : b < 1024 ? `${b}B`
      : b < 1048576 ? `${(b / 1024).toFixed(1)}KB`
      : `${(b / 1048576).toFixed(2)}MB`;

  const fmtTok = n => n == null ? 'n/a' : `${Math.round(n)} tok`;

  // Self-calibrating chars/token: averaged from turns where the stream reported
  // real input usage; falls back to EST_CHARS_PER_TOKEN until we have a sample.
  let calChars = 0, calTokens = 0;
  const charsPerToken = () => calTokens > 0 ? calChars / calTokens : EST_CHARS_PER_TOKEN;
  const estimateTokens = chars =>
    chars == null ? null : Math.round(chars / charsPerToken());

  const byteLen = s => { try { return encoder.encode(s).length; } catch { return null; } };

  const tryParse = s => { try { return JSON.parse(s); } catch { return null; } };

  // Copy a value to the clipboard as pretty JSON; on failure (tab unfocused, no
  // permission) fall back to logging it so it can still be copied by hand.
  const copyJson = (value, okMsg) => {
    const json = JSON.stringify(value, null, 2);
    navigator.clipboard.writeText(json)
      .then(() => console.log(okMsg))
      .catch(() => console.log(json));
  };

  // Build the compact hud_audit snapshot. Shared by audit() (clipboard) and
  // auditInject() (composer), so the two paths can never drift apart.
  function buildAuditSnapshot() {
    const s = window._claudeDebug.summary;
    const data = turnLog.map(t => ({
      rowKey: `${SESSION_NONCE}:${t.id}`,   // globally unique across reloads/pastes (id alone is not)
      id: t.id, ts: t.ts, conv: t.conv || null, model: t.model || null,
      isCompletion: !!t.isCompletion, isRetry: !!t.isRetry, via: t.via || 'fetch',
      ttft: t.ttft, ttftText: t.ttftText ?? null, total: t.total, streamMs: t.streamDuration,
      // inTok measures only the NEW turn body (claude.ai sends prior turns by UUID),
      // NOT full reprocessed context — flagged so the reader never treats it as such.
      inTok: t.inputTokens, inTokNewTurnOnly: true, inputApprox: !!t.inputApprox,
      outTok: t.outputTokens,
      thinkTok: t.thinkingChars ? estimateTokens(t.thinkingChars) : 0,
      answerTok: t.answerChars ? estimateTokens(t.answerChars) : 0,
      tokPerSec: t.tokPerSec, gapP95: t.interEventP95,
      stop: t.stopReason || null, src: t.tokensReal ? 'API' : '~', status: t.status,
    }));
    const qWindows = quotaWindowsSnapshot();
    return {
      tag: 'hud_audit', schemaVersion: SCHEMA_VERSION, at: new Date().toISOString(),
      sessionNonce: SESSION_NONCE, sessionStart: SESSION_START,
      plan: detectedPlan,                 // free|pro|max|… or null if not seen
      tokenSource: s.tokenSource,         // 'api' only on the keyed Anthropic API; 'estimated' on claude.ai subscriptions
      sessionMs: s.sessionMs, chatMs: s.chatMs, engagedMs: s.engagedMs,
      // turns = every recorded SSE stream; the counts below break that down so a
      // ledger can do message-cap math without re-deriving it from rows.
      turns: s.turns, completions: s.completions, retries: s.retries,
      nonCompletionStreams: s.nonCompletionStreams, domTurns: domTurnCount(),
      exactTurns: s.exactTurns, tokensTotal: s.tokensTotal,
      tokensApprox: s.exactTurns === 0,   // true on any subscription account
      charsPerToken: Number(charsPerToken().toFixed(2)), charsPerTokenCalibrated: s.calTokens > 0,
      medianTotalMs: s.medianTotalMs, p90TotalMs: s.p90TotalMs, medianTTFTMs: s.medianTTFTMs,
      msgsLastHour: s.msgsLastHour, msgsLast24h: s.msgsLast24h,
      cappedAtMaxTurns: s.cappedAtMaxTurns,   // window is truncated if true
      stopReasons: stopReasonDistribution(),
      streamErrors: streamErrorCount,
      quota: qWindows.length ? qWindows : latestQuota(),   // persisted rolling windows (the real subscription signal)
      quotaWindows: qWindows,
      data,
    };
  }

  // Locate claude.ai's message composer (a ProseMirror contenteditable). Most
  // specific selector first, then progressively looser fallbacks in case the
  // markup shifts.
  function findComposer() {
    return document.querySelector('div.ProseMirror[contenteditable="true"]')
        || document.querySelector('[contenteditable="true"][role="textbox"]')
        || document.querySelector('main [contenteditable="true"]')
        || document.querySelector('[contenteditable="true"]');
  }

  // INJECT-ONLY: insert `text` at the composer caret and stop. Never clicks Send —
  // you review and submit by hand. Goes through execCommand('insertText') so the
  // input flows through ProseMirror's own pipeline (a raw innerText/value set is
  // silently dropped when you hit Send); a beforeinput event is the secondary path.
  // If no composer is found or both inserts are rejected, the text is left on the
  // clipboard with a console note so nothing is lost.
  function injectIntoComposer(text, okMsg) {
    const fallbackToClipboard = (why) =>
      navigator.clipboard.writeText(text)
        .then(() => console.warn(`hud_audit: ${why} — text left on clipboard instead; paste it manually.`))
        .catch(() => console.log(text));
    const el = findComposer();
    if (!el) { fallbackToClipboard('composer not found'); return false; }
    el.focus();
    // dispatchEvent's return value is NOT a reliable "did it insert" signal (it's
    // false only when preventDefault was called, true even when nothing changed),
    // so verify against the actual DOM instead.
    const sig = (text.trim().split(/\s+/)[0] || text.slice(0, 8));
    const before = el.textContent;
    const landed = () => el.textContent !== before && el.textContent.includes(sig);
    try { document.execCommand('insertText', false, text); } catch (_) {}
    if (!landed()) {
      // last resort: a synthetic (untrusted) beforeinput; many editors ignore it,
      // hence the DOM re-check rather than trusting the dispatch.
      try {
        el.dispatchEvent(new InputEvent('beforeinput',
          { inputType: 'insertText', data: text, bubbles: true, cancelable: true }));
      } catch (_) {}
    }
    if (!landed()) { fallbackToClipboard('composer did not accept the insert'); return false; }
    console.log(okMsg);
    return true;
  }

  // Turn-log column helpers (used across stats/summary/assessment/rates).
  // col(key): finite values of one field across all turns. median(): linear-
  // interpolation median of a value list. sumBy(): summed finite field over a set.
  const col    = key => turnLog.map(t => t[key]).filter(Number.isFinite);
  const median = vals => { const a = [...vals].filter(Number.isFinite).sort((x, y) => x - y); return a.length ? quantile(a, 0.5) : null; };
  const sumBy  = (arr, key) => arr.reduce((a, t) => a + (Number.isFinite(t[key]) ? t[key] : 0), 0);

  // Status icons — one source of truth for the probe/assessment verdicts.
  const ICON = { pass: '✅', warn: '⚠️', fail: '❌', info: 'ℹ️' };

  // Detect base64/data-URI blobs (image & file attachments). Counting these as
  // chars/token wildly overstates input — Claude tokenizes images by tiles, not by
  // base64 length — so we EXCLUDE them from the char estimate (their real bytes
  // still show up in reqBytes / transfer sizes).
  const DATA_URI_RE = /^data:[^;,]*;base64,/i;
  function looksLikeBase64Blob(s) {
    if (s.length < 256) return false;
    if (DATA_URI_RE.test(s)) return true;
    return s.length > 1024 && /^[A-Za-z0-9+/=\r\n]+$/.test(s);
  }

  // Sum the length of every string LEAF in a JSON-ish value (iterative, capped),
  // skipping base64 blobs. Keys are not counted, so the estimate tracks content,
  // not framing.
  function extractStringChars(root, stats) {
    let total = 0, nodes = 0;
    const stack = [root];
    while (stack.length) {
      const x = stack.pop();
      if (++nodes > 20000 || total > BODY_SCAN_MAX) break;   // guard against pathological payloads
      if (typeof x === 'string') {
        if (looksLikeBase64Blob(x)) { if (stats) stats.attachments++; }
        else total += x.length;
      }
      else if (Array.isArray(x)) for (const e of x) stack.push(e);
      else if (x && typeof x === 'object') for (const k in x) stack.push(x[k]);
    }
    return total;
  }

  // Output sizing from one SSE event. Returns a SIGNED char count: positive =
  // visible answer (text / tool-call JSON), negative = thinking/summary, 0 =
  // metadata/framing (stop_reason, message, display_content, ping, ...). A delta is
  // a single type, so answer and thinking never co-occur in one event — the sign
  // carries the split with zero per-event allocation.
  function outputCharsFromEvent(obj) {
    const d = obj && obj.delta;
    if (d) {
      if (typeof d.text === 'string')         return d.text.length;
      if (typeof d.partial_json === 'string') return d.partial_json.length;   // tool-call args
      if (typeof d.thinking === 'string')     return -d.thinking.length;      // thinking
      if (typeof d.summary === 'string')      return -d.summary.length;       // summarized reasoning
      return 0;                                                               // metadata-only delta
    }
    if (typeof (obj && obj.completion) === 'string') return obj.completion.length;   // legacy shape
    if (obj && obj.content_block && typeof obj.content_block.text === 'string') return obj.content_block.text.length;
    return 0;                                                                 // ping / framing-only event
  }

  function isPingEvent(obj) { return !!(obj && obj.type === 'ping'); }

  // Pull a usage object out of an SSE event if the stream exposes one (keyless,
  // exact when present). message_start carries input + cache tokens; message_delta
  // carries running output tokens. Returns null if absent.
  function usageFromEvent(obj) {
    if (!obj) return null;
    return obj.usage || (obj.message && obj.message.usage) || null;
  }

  // ─── Schema probe ───────────────────────────────────────────────────────────
  // Arm via the 🔬 button or _claudeDebug.probe(); the next monitored SSE turn is
  // analyzed (KEYS only, never content) and a PASS/WARN/FAIL report is printed.
  function runSchemaProbe() {
    probeArmed = true;
    renderResultHud('🔬 Schema probe armed', 'info', ['Send ONE message. The next streamed turn is analyzed; the verdict shows here (and in the console).']);
    console.log('%c🔬 Schema probe armed — send ONE message; the next streamed turn is analyzed and a report prints here.',
      'color:#6c47ff;font-weight:bold');
  }

  function collectProbe(p, obj) {
    p.samples++;
    if (obj.type) p.types.add(obj.type);
    if (obj.type === 'error') { p.sawError = true; p.errorType = (obj.error && (obj.error.type || obj.error.message)) || 'error'; }
    for (const k in obj) p.topKeys.add(k);
    if (obj.type === 'message_limit') {
      for (const k in obj) p.limitKeys.add(k);
      if (obj.message_limit && typeof obj.message_limit === 'object')
        for (const k in obj.message_limit) p.limitKeys.add('message_limit.' + k);
    }
    const u = usageFromEvent(obj);
    if (u) for (const k in u) p.usageFields.add(k);
    const d = obj.delta;
    if (d && typeof d === 'object') {
      for (const k in d) p.deltaKeys.add(k);
      if (typeof d.text === 'string' || typeof d.partial_json === 'string' ||
          typeof d.thinking === 'string' || typeof d.summary === 'string') p.known = true;
      else if (DELTA_META_KEYS.some(k => k in d)) { /* metadata-only delta: expected, not a content gap */ }
      else p.unknown = true;
    }
  }

  function reportProbe(r) {
    const P = ICON.pass, W = ICON.warn, F = ICON.fail, I = ICON.info;
    const m = r.meta || {};
    const lines = [];
    if (r.reqParsedKeys && r.reqParsedKeys.length)
      lines.push(`${P} request body parsed (keys: ${r.reqParsedKeys.join(', ')}); ~${r.inChars} content chars` +
        (r.inputApprox ? ' (approx — body over the scan cap)' : '') +
        (r.attachments ? `; ${r.attachments} inlined blob(s) excluded (images = tiles, not chars)` : ''));
    else
      lines.push(`${W} request body NOT parsed as JSON — input estimate falls back to raw length`);
    lines.push(`${I} input is NEW-TURN ONLY — claude.ai sends prior turns by reference (turn_message_uuids), not inlined, so this is not full-context input`);
    if (m.model || m.thinkingMode != null || m.effort != null)
      lines.push(`${I} model ${m.model || '?'}${m.thinkingMode != null ? ` · thinking_mode=${m.thinkingMode}` : ''}${m.effort != null ? ` · effort=${m.effort}` : ''} · tools ${m.toolCount || 0} · attachments ${m.attachmentCount || 0}`);
    lines.push(`${r.isCompletion ? P : W} endpoint "${r.endpoint}" ${r.isCompletion ? 'classified as a completion (counts as a message)' : 'NOT matched as a completion — check COMPLETION_RE if this was a chat turn'}`);
    lines.push(`${r.conv ? P : W} conversation id ${r.conv ? `parsed (${r.conv})` : 'NOT parsed from URL — convOf regex may be stale'}`);
    if (r.probe.usageFields.size) {
      const f = [...r.probe.usageFields];
      const ok = f.includes('input_tokens') && f.includes('output_tokens');
      lines.push(`${ok ? P : W} usage object present (fields: ${f.join(', ')}) → tokens are EXACT` +
        (ok ? '' : '; missing input_tokens/output_tokens — only partial exactness'));
    } else {
      lines.push(`${I} no usage object — EXPECTED on claude.ai (its internal stream omits usage); tokens are heuristic (~chars/${charsPerToken().toFixed(2)})` +
        (r.probe.limitKeys && r.probe.limitKeys.size ? `. A message_limit event was seen (keys: ${[...r.probe.limitKeys].join(', ')}) — may carry quota/usage data.` : ''));
    }
    if (r.probe.sawError)
      lines.push(`${F} stream returned an ERROR event (${r.probe.errorType}) — the turn produced no content; this is a claude.ai error/limit response, NOT a parser problem`);
    else if (r.probe.known && !r.probe.unknown)
      lines.push(`${P} content deltas recognized (text / thinking / summary / partial_json) → output sizing is sound`);
    else if (r.probe.known && r.probe.unknown)
      lines.push(`${W} a delta shape wasn't recognized as content (keys seen: ${[...r.probe.deltaKeys].join(', ')}) — verify outputCharsFromEvent()`);
    else if (r.probe.unknown)
      lines.push(`${F} delta present but UNRECOGNIZED (keys: ${[...r.probe.deltaKeys].join(', ')}) → output estimate unreliable; update outputCharsFromEvent()`);
    else
      lines.push(`${W} no content deltas seen this turn`);
    if (r.probe.types.has('compaction_status')) lines.push(`${I} a compaction_status event was seen — claude.ai compacted this conversation's context mid-stream`);
    const problems = lines.filter(l => l.startsWith(F) || l.startsWith(W)).length;
    const typesLine = `event types: ${[...r.probe.types].join(', ') || '(none)'}`;
    const summary = problems ? `${W} ${problems} potential problem(s) flagged above.` : `${P} No problems — the parser matches the live shapes.`;
    // "completion #N · request #id" when this was a completion; just the request id otherwise.
    // N counts completions this session; the request id counts every monitored /api/ call.
    const label = r.completionSeq != null ? `completion #${r.completionSeq} · request #${r.id}` : `request #${r.id}`;
    console.group(`🔬 Schema probe — ${label} (${r.probe.samples} events sampled)`);
    for (const l of lines) console.log(l);
    console.log(typesLine);
    console.log(summary);
    console.groupEnd();
    const status = lines.some(l => l.startsWith(F)) ? 'fail' : problems ? 'warn' : 'ok';
    renderResultHud(`🔬 Schema probe — ${label} (${r.probe.samples} events)`, status, [...lines, typesLine, summary]);
    probeArmed = false;
  }

  // "cache;desc=HIT, db;dur=42.1" -> { cache:{desc:'HIT'}, db:{dur:42.1} }
  function parseServerTiming(h) {
    const out = {};
    for (const part of h.split(',')) {
      const segs = part.split(';').map(s => s.trim()).filter(Boolean);
      if (!segs.length) continue;
      const m = {};
      for (const s of segs.slice(1)) {
        const eq = s.indexOf('=');
        if (eq < 0) continue;
        const k = s.slice(0, eq).trim(), v = s.slice(eq + 1).trim();
        m[k] = k === 'dur' ? Number(v) : v.replace(/^"|"$/g, '');
      }
      out[segs[0]] = m;
    }
    return out;
  }

  // Collect anthropic-ratelimit-* / retry-after headers if present (closest
  // keyless proxy for remaining capacity).
  function captureRateLimit(headers) {
    const rl = {};
    headers.forEach((v, k) => {
      const lk = k.toLowerCase();
      if (lk.startsWith('anthropic-ratelimit') || lk === 'retry-after' ||
          lk.startsWith('x-ratelimit') || lk.startsWith('ratelimit-')) {
        rl[lk] = /^\d+$/.test(v) ? Number(v) : v;
      }
    });
    return Object.keys(rl).length ? rl : null;
  }

  // Cross-engine caller attribution (V8 prefixes an "Error" line; Firefox/Safari
  // don't). Drop our own wrapper frame and take the next few caller frames.
  function callerStack() {
    const raw = (new Error().stack || '').split('\n').filter(Boolean);
    const frames = raw[0] && raw[0].trim().startsWith('Error') ? raw.slice(1) : raw;
    return frames.slice(1, 1 + STACK_CALLER_FRAMES).map(s => s.trim()).join(' | ');
  }

  function isMonitoredHost(host) {
    return API_HOSTS.some(h => host === h || host.endsWith('.' + h));
  }

  function isMonitoredApi(rawUrl) {
    try {
      const u = new URL(rawUrl, location.href);
      return isMonitoredHost(u.hostname) && u.pathname.startsWith('/api/');
    } catch { return false; }
  }

  function pathOf(rawUrl) {
    try { return new URL(rawUrl, location.href).pathname; } catch { return rawUrl; }
  }

  // Best-effort conversation id from the URL path (undocumented; may change).
  function convOf(rawUrl) {
    try {
      const m = new URL(rawUrl, location.href).pathname.match(/chat_conversations\/([0-9a-f-]{8,})/i);
      return m ? m[1].slice(0, 8) : null;
    } catch { return null; }
  }

  // Organization id from any /api/organizations/<uuid>/… URL. Latched once so
  // refreshQuota() can hit /api/organizations/<id>/usage on demand.
  function noteOrg(rawUrl) {
    if (orgId) return;
    try {
      const m = new URL(rawUrl, location.href).pathname.match(/organizations\/([0-9a-f-]{8,})/i);
      if (m) orgId = m[1];
    } catch { /* ignore */ }
  }

  // Group key for the per-endpoint tally: the last path segment, but if that segment
  // is id-like (uuid / hex / all-digits) it's folded to "<parent>/:id" so every
  // conversation/message id doesn't become its own row. Query string is ignored.
  function endpointKey(rawUrl) {
    const segs = pathOf(rawUrl).split('/').filter(Boolean);
    if (!segs.length) return '/';
    const last = segs[segs.length - 1];
    const idish = /^[0-9a-f-]{8,}$/i.test(last) || /^\d+$/.test(last);
    return (idish && segs.length >= 2) ? `${segs[segs.length - 2]}/:id` : last;
  }

  // Pull useful per-turn metadata from claude.ai's request body (best-effort; the
  // internal completion shape, confirmed via the schema probe: model, thinking_mode,
  // effort, tools, attachments, files, sync_sources).
  function requestMeta(obj) {
    if (!obj || typeof obj !== 'object') return {};
    const len = v => Array.isArray(v) ? v.length : 0;
    return {
      model: typeof obj.model === 'string' ? obj.model : null,
      thinkingMode: obj.thinking_mode != null ? obj.thinking_mode : null,
      effort: obj.effort != null ? obj.effort : null,
      toolCount: len(obj.tools),
      attachmentCount: len(obj.attachments) + len(obj.files),
      syncSources: len(obj.sync_sources),
    };
  }

  // Size the outgoing request body and estimate its input tokens — CONTENT IS NOT
  // LOGGED, only measured. Handles string bodies AND the Request-object case
  // (fetch(new Request(...)) with the body on `input`, not `init`). The Request
  // clone is taken synchronously (before the first await) so it happens before
  // origFetch consumes the body — callers must invoke this BEFORE dispatching fetch.
  async function analyzeBody(input, init) {
    let str = null, bytes = null;
    const initBody = init && 'body' in init ? init.body : undefined;
    if (typeof initBody === 'string') {
      str = initBody;
    } else if (initBody != null) {
      if (typeof Blob !== 'undefined' && initBody instanceof Blob) bytes = initBody.size;
      else if (initBody instanceof ArrayBuffer) bytes = initBody.byteLength;
      else if (typeof URLSearchParams !== 'undefined' && initBody instanceof URLSearchParams) str = initBody.toString();
      // FormData / ReadableStream: size unknown without consuming — skip.
    } else if (typeof Request !== 'undefined' && input instanceof Request) {
      try { str = await input.clone().text(); } catch { str = null; }   // clone() runs sync, before the await
    }
    if (str != null) {
      // claude.ai references prior turns by UUID (turn_message_uuids), so the body holds
      // only the NEW turn — inChars is new-turn input, NOT full context. Over BODY_SCAN_MAX
      // we also skip the parse + per-leaf walk (and the full byte encode) and approximate.
      if (str.length > BODY_SCAN_MAX) {
        return {
          reqBytes: str.length, estInputTokens: estimateTokens(str.length),
          inChars: str.length, attachments: 0, topKeys: [], inputApprox: true, meta: {},
        };
      }
      const obj = tryParse(str);
      const stats = { attachments: 0 };
      const chars = obj ? extractStringChars(obj, stats) : str.length;
      return {
        reqBytes: byteLen(str), estInputTokens: estimateTokens(chars),
        inChars: chars, attachments: stats.attachments,
        topKeys: obj && typeof obj === 'object' ? Object.keys(obj) : [],
        inputApprox: false, meta: requestMeta(obj),
      };
    }
    return { reqBytes: bytes, estInputTokens: null, inChars: null, attachments: 0, topKeys: [], inputApprox: false, meta: {} };
  }

  // ─── Recording ──────────────────────────────────────────────────────────────
  function recordTurn(entry) {
    entry.ts = Date.now();
    // Chat span + engaged time should track user-visible messages, not background
    // SSE (title generation, etc.) or retries, so only completions advance them.
    if (entry.isCompletion && !entry.isRetry) {
      if (firstTurnTs == null) firstTurnTs = entry.ts;
      lastTurnTs = entry.ts;
      if (Number.isFinite(entry.total)) engagedMs += entry.total;
    }
    // Any turn that carried a message_limit refreshes the persisted quota windows.
    if (entry.messageLimit) persistQuota(entry.messageLimit);

    // [SLOW]: flag turns above the session p90. Recompute the baseline every
    // SLOW_P90_REFRESH turns instead of sorting the whole log on every turn.
    if (turnLog.length >= SLOW_MIN_SAMPLES) {
      if (slowP90 == null || turnLog.length - slowP90At >= SLOW_P90_REFRESH) {
        const st = calcStats(turnLog.map(t => t.total).filter(Number.isFinite));
        slowP90 = st ? st.p90 : null; slowP90At = turnLog.length;
      }
      if (slowP90 != null && Number.isFinite(entry.total) && entry.total > slowP90) {
        console.warn(`[SLOW #${entry.id}] ${fmtMs(entry.total)} > session p90 ${fmtMs(slowP90)}`);
      }
    }

    turnLog.push(entry);
    if (turnLog.length > MAX_TURNS) turnLog.shift();

    console.groupCollapsed(`[PERF #${entry.id}] turn complete`);
    console.log('  status:            ', entry.status);
    if (entry.conv) console.log('  conversation:      ', entry.conv);
    console.log('  TTFT (1st chunk):  ', fmtMs(entry.ttft),           '← server think + network');
    console.log('  TTFT (1st event):  ', fmtMs(entry.ttftEvent),      '← first decoded SSE event');
    console.log('  streaming duration:', fmtMs(entry.streamDuration), '← response generation time');
    console.log('  total turn time:   ', fmtMs(entry.total),          '← wall clock send→done');
    console.log('  SSE events / reads:', `${entry.events} / ${entry.reads}`);
    const mark = entry.tokensReal ? '' : '~';
    const tokSrc = entry.tokensReal ? '(API exact)' : `(est ~chars/${charsPerToken().toFixed(2)})`;
    console.log('  request:           ', `${fmtBytes(entry.reqBytes)}  ${mark}${fmtTok(entry.inputTokens)} ${tokSrc}` +
      (entry.attachments ? `  +${entry.attachments} attachment(s) [not token-counted]` : ''));
    console.log('  response stream:   ', `${fmtBytes(entry.streamBytes)}  ${mark}${fmtTok(entry.outputTokens)} ${tokSrc}`);
    if (entry.thinkingChars) console.log('  thinking / answer: ', `~${estimateTokens(entry.thinkingChars)} + ~${estimateTokens(entry.answerChars)} tok (heuristic split)`);
    if (entry.thinkingShare != null) console.log('  thinking share:    ', `${Math.round(entry.thinkingShare * 100)}% of output was reasoning`);
    if (entry.reasonedMs != null) console.log('  reasoned first:    ', `${entry.reasonedMs} ms thinking before the first answer token`);
    if (entry.answerTokPerSec != null) console.log('  answer tok/s:      ', `${entry.answerTokPerSec} (answer-only, excludes thinking)`);
    if (entry.streamError) console.log('  \u26a0 stream error:   ', entry.streamError);
    if (entry.ttftText != null) console.log('  TTF-text:          ', fmtMs(entry.ttftText), '← first visible text (perceived latency)');
    if (entry.stopReason) console.log('  stop reason:       ', entry.stopReason + (entry.stopDetails ? ` ${JSON.stringify(entry.stopDetails)}` : ''));
    if (entry.model) console.log('  model / mode:      ', `${entry.model}${entry.thinkingMode != null ? ' · thinking=' + entry.thinkingMode : ''}${entry.effort != null ? ' · effort=' + entry.effort : ''} · tools ${entry.toolCount || 0} · att ${entry.attachmentCount || 0}`);
    if (entry.messageLimit) { const _q = quotaSummary(entry.messageLimit); console.log('  message_limit:     ', _q ? fmtQuotaLine(_q) : entry.messageLimit); }
    if (entry.cacheRead != null || entry.cacheCreate != null) {
      const totalCtx = (entry.inputTokens || 0) + (entry.cacheRead || 0) + (entry.cacheCreate || 0);
      console.log('  cache tokens:      ', `read ${entry.cacheRead ?? 0} / create ${entry.cacheCreate ?? 0}  (total ctx ~${totalCtx})`);
    }
    console.log('  throughput:        ', entry.tokPerSec == null ? 'n/a'
      : `${mark}${entry.tokPerSec} tok/s steady · ${mark}${entry.tokPerSecWall ?? '?'} tok/s wall`);
    if (entry.interEventP50 != null)
      console.log('  inter-event gap:   ', `p50 ${entry.interEventP50}ms / p95 ${entry.interEventP95}ms`);
    console.log('  endpoint:          ', `${entry.endpoint}${entry.isCompletion ? '' : ' (non-completion)'}`);
    console.log('  url:               ', entry.url);
    console.groupEnd();
  }

  // ─── Stats ──────────────────────────────────────────────────────────────────
  // Linear-interpolation quantile (proper median for even n; p90 no longer pinned
  // to max on small samples).
  function quantile(sorted, q) {
    if (!sorted.length) return null;
    if (sorted.length === 1) return sorted[0];
    const pos = (sorted.length - 1) * q;
    const lo = Math.floor(pos), hi = Math.ceil(pos);
    return lo === hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  function calcStats(values) {
    if (!values.length) return null;
    const sorted = [...values].sort((a, b) => a - b);
    return {
      n:      sorted.length,
      min:    sorted[0],
      max:    sorted[sorted.length - 1],
      median: quantile(sorted, 0.5),
      p90:    quantile(sorted, 0.9),
    };
  }

  function printStats() {
    if (!turnLog.length) { console.log('No turns recorded yet.'); return; }
    const fmtRow = s => !s ? 'n/a'
      : `min ${fmtMs(s.min)} / med ${fmtMs(s.median)} / p90 ${fmtMs(s.p90)} / max ${fmtMs(s.max)} (n=${s.n})`;

    console.group('📊 Turn latency summary');
    console.log('  TTFT (chunk):      ', fmtRow(calcStats(col('ttft'))));
    console.log('  TTFT (event):      ', fmtRow(calcStats(col('ttftEvent'))));
    console.log('  Streaming duration:', fmtRow(calcStats(col('streamDuration'))));
    console.log('  Total turn time:   ', fmtRow(calcStats(col('total'))));
    console.groupEnd();
  }

  // ─── ASCII histogram ──────────────────────────────────────────────────────────
  const MS_METRICS    = new Set(['total', 'ttft', 'ttftEvent', 'streamDuration', 'interEventP95']);
  const BYTE_METRICS  = new Set(['reqBytes', 'streamBytes']);
  const METRIC_LABEL = {
    total: 'Total turn time', ttft: 'Time-to-first-chunk', ttftEvent: 'Time-to-first-event',
    streamDuration: 'Streaming duration',
    outputTokens: 'Output tokens', inputTokens: 'Input tokens',
    tokPerSec: 'Tokens/sec (steady)', tokPerSecWall: 'Tokens/sec (wall)',
    interEventP95: 'Inter-event p95 (ms)', cacheRead: 'Cache-read tokens',
    reqBytes: 'Request bytes', streamBytes: 'Response bytes',
  };

  function fmtForMetric(metric) {
    if (MS_METRICS.has(metric)) return fmtMs;
    if (BYTE_METRICS.has(metric)) return fmtBytes;
    return v => `${Math.round(v)}`;
  }

  // Shared histogram computation used by both the console printer and the HUD panel.
  function histogramData(metric = 'total', buckets = 5) {
    const fmt = fmtForMetric(metric);
    const label = METRIC_LABEL[metric] ?? metric;
    const values = col(metric).filter(v => v >= 0);
    if (values.length < 2) return { metric, label, n: values.length, note: 'Not enough data (need 2+ turns).' };
    const min = Math.min(...values), max = Math.max(...values);
    if (max === min) return { metric, label, n: values.length, single: fmt(min) };
    const width = (max - min) / buckets;
    const counts = Array(buckets).fill(0);
    for (const v of values) counts[Math.min(Math.floor((v - min) / width), buckets - 1)]++;
    const maxCount = Math.max(...counts);
    const rows = counts.map((c, i) => {
      const lo = min + i * width, hi = lo + width;
      return { lo: fmt(lo), hi: fmt(hi), count: c, frac: maxCount ? c / maxCount : 0 };
    });
    return { metric, label, n: values.length, rows };
  }

  function printHistogram(metric = 'total', buckets = 5) {
    const h = histogramData(metric, buckets);
    if (h.note) { console.log('Not enough data for histogram yet (need 2+ turns).'); return; }
    console.log(`\n📊 Histogram — ${h.label} (${h.n} turns)\n`);
    if (h.single) { console.log(`  all ${h.n} turns ≈ ${h.single}`); console.log(''); return; }
    for (const r of h.rows) {
      const bar = '█'.repeat(Math.round(r.frac * BAR_WIDTH));
      const pad = ' '.repeat(BAR_WIDTH - bar.length);
      console.log(`  ${String(r.lo).padStart(8)}–${String(r.hi).padEnd(8)}  ${bar}${pad}  ${r.count}`);
    }
    console.log('');
  }

  // ─── Rolling rates ──────────────────────────────────────────────────────────
  const RATE_WINDOWS = [['1m', 60000], ['5m', 300000], ['1h', 3600000], ['24h', 86400000]];

  let ratesCacheKey = '', ratesCacheVal = null;
  function ratesSnapshot() {
    const now = Date.now();
    const ck = turnLog.length + ':' + Math.floor(now / 1000);   // recompute at most ~1x/sec
    if (ck === ratesCacheKey && ratesCacheVal) return ratesCacheVal;
    const snap = RATE_WINDOWS.map(([label, ms]) => {
      const inWin = turnLog.filter(t => now - t.ts <= ms);
      const sum = key => sumBy(inWin, key);
      return {
        window: label,
        messages: inWin.length,
        completions: inWin.filter(t => t.isCompletion).length,
        freshCompletions: inWin.filter(t => t.isCompletion && !t.isRetry).length,
        retries: inWin.filter(t => t.isRetry).length,
        exact: inWin.filter(t => t.tokensReal).length,
        inTokens: sum('inputTokens'),
        outTokens: sum('outputTokens'),
        cacheRead: sum('cacheRead'),
        cacheCreate: sum('cacheCreate'),
        bytesUp: sum('reqBytes'),
        bytesDown: sum('streamBytes'),
      };
    });
    ratesCacheKey = ck; ratesCacheVal = snap;
    return snap;
  }

  function printRates() {
    if (!turnLog.length) { console.log('No turns recorded yet.'); return; }
    const snap = ratesSnapshot();
    console.group('📈 Usage rates');
    console.table(snap.map(r => ({
      window: r.window,
      streams: r.messages,
      completions: r.completions,
      'in tok': r.inTokens,
      'out tok': r.outTokens,
      'in+cache': r.inTokens + r.cacheRead + r.cacheCreate,
      'cache rd': r.cacheRead,
      'exact/total': `${r.exact}/${r.messages}`,
      up: fmtBytes(r.bytesUp),
      down: fmtBytes(r.bytesDown),
    })));
    const oneH = snap.find(r => r.window === '1h');
    if (oneH) {
      console.log(`Projected at the last-hour rate: ~${oneH.completions * 24} completions/day, ` +
        `~${(oneH.inTokens + oneH.outTokens) * 24} fresh tok/day ` +
        `(in/out are EXACT for ${oneH.exact}/${oneH.messages} turns, else ~chars/${charsPerToken().toFixed(2)}; "in+cache" = new-turn input + cache, NOT full context on claude.ai).`);
    }
    console.groupEnd();
  }

  function byConversation() {
    const groups = new Map();
    for (const t of turnLog) {
      const k = t.conv || '(none)';
      const g = groups.get(k) || { conversation: k, messages: 0, inTokens: 0, outTokens: 0, cacheRead: 0, exact: 0 };
      g.messages++;
      g.inTokens += Number.isFinite(t.inputTokens) ? t.inputTokens : 0;
      g.outTokens += Number.isFinite(t.outputTokens) ? t.outputTokens : 0;
      g.cacheRead += Number.isFinite(t.cacheRead) ? t.cacheRead : 0;
      if (t.tokensReal) g.exact++;
      groups.set(k, g);
    }
    console.table([...groups.values()].map(g => ({ ...g, src: `${g.exact}/${g.messages} API` })));
  }

  // ─── Assessment: outliers + efficiency, relative to THIS session ────────────
  function runAssessment() {
    const n = turnLog.length;
    if (n < 3) { console.log(`Need ≥3 completed turns to assess (have ${n}).`); renderResultHud('💡 Assessment', 'info', ['Need at least 3 completed turns before assessing (have ' + n + ').']); return; }
    const totals = col('total');
    const sT = calcStats(totals), sTtft = calcStats(col('ttft'));
    const medTotal = sT.median, p90Total = sT.p90;
    const find = [], rec = [];

    const slow = turnLog.filter(t => Number.isFinite(t.total) && t.total > p90Total && t.total > ASSESS.slowVsMedian * medTotal)
      .sort((a, b) => b.total - a.total).slice(0, 3);
    for (const t of slow) {
      const cause = (Number.isFinite(t.ttft) && t.ttft > 0.5 * t.total) ? 'server/network latency (TTFT-dominated)' : 'long output (streaming-dominated)';
      find.push(`${ICON.warn} turn #${t.id}: ${(t.total / medTotal).toFixed(1)}× your median (${fmtMs(t.total)}) — ${cause}`);
    }
    if (!slow.length) find.push(`${ICON.pass} latency consistent — no turn beat ${ASSESS.slowVsMedian}× median & p90`);

    if (sTtft && sTtft.median > 0 && sTtft.p90 > ASSESS.ttftSpike * sTtft.median)
      find.push(`${ICON.warn} TTFT spiky: p90 ${fmtMs(sTtft.p90)} vs median ${fmtMs(sTtft.median)} — intermittent server slowness`);

    const medIn = median(col('inputTokens')), medOut = median(col('outputTokens'));
    if (medIn != null && medOut) {
      const ratio = medIn / medOut;
      if (ratio > ASSESS.inOutRatio) { find.push(`${ICON.warn} input:output ≈ ${ratio.toFixed(0)}:1 — lots of context per unit of answer`); rec.push('High input:output — if answers are short, a fresh chat or trimming pasted context cuts latency/cost.'); }
      else find.push(`${ICON.pass} input:output ≈ ${ratio.toFixed(1)}:1 — reasonable`);
    }

    const ins = col('inputTokens');
    if (ins.length >= 4 && ins[0] > 0 && ins[ins.length - 1] / ins[0] > ASSESS.ctxGrowth) {
      const g = (ins[ins.length - 1] / ins[0]).toFixed(1);
      find.push(`${ICON.warn} input grew ${g}× since the oldest retained turn (${ins[0]}→${ins[ins.length - 1]} tok) — context bloat`);
      rec.push(`Context grew ${g}× — a long thread re-sends everything each turn; a new chat (or a summary) speeds TTFT and cuts tokens.`);
    }

    const realTurns = turnLog.filter(t => t.tokensReal);
    if (realTurns.length >= 3) {
      const cr = sumBy(realTurns, 'cacheRead'), it = sumBy(realTurns, 'inputTokens'), cc = sumBy(realTurns, 'cacheCreate');
      const denom = cr + it + cc, hit = denom > 0 ? cr / denom : 0;
      if (hit < ASSESS.cacheHitLow && n >= 6) { find.push(`${ICON.warn} cache hit ~${(hit * 100).toFixed(0)}% over ${realTurns.length} turns — caching isn't carrying much context`); rec.push("Low cache reuse — editing earlier messages or changing the system prompt/tools invalidates the cache; avoid editing history to keep it warm."); }
      else find.push(`${ICON.pass} cache hit ~${(hit * 100).toFixed(0)}% — caching is doing its job`);
    } else {
      find.push(`${ICON.info} tokens are heuristic (no real usage) — efficiency/cache estimates limited; run the 🔬 probe to confirm the schema`);
    }

    const tpsMed = median(col('tokPerSec'));
    if (tpsMed) {
      const dips = turnLog.filter(t => Number.isFinite(t.tokPerSec) && t.tokPerSec < ASSESS.tpsDip * tpsMed).sort((a, b) => a.tokPerSec - b.tokPerSec).slice(0, 2);
      for (const t of dips) find.push(`${ICON.warn} turn #${t.id} generated ~${t.tokPerSec} tok/s vs ~${Math.round(tpsMed)} median — degraded throughput`);
    }

    const errs = [...statusCounts.entries()].filter(([s]) => s >= 400);
    if (failCount || errs.length) { find.push(`${ICON.warn} ${failCount} fetch failure(s)${errs.length ? `, statuses ${errs.map(([s, c]) => s + '×' + c).join(', ')}` : ''}`); rec.push('Errors/retries seen — check connectivity or rate limits (rateLimits()).'); }

    const truncN = turnLog.filter(t => t.stopReason === 'max_tokens').length;
    if (truncN) { find.push(`${ICON.warn} ${truncN}/${n} turns hit max_tokens (output truncated)`); rec.push('Truncation: answers are being cut at the output cap — request continuation or narrow scope.'); }
    if (streamErrorCount) find.push(`${ICON.warn} ${streamErrorCount} stream error event(s) this session (claude.ai returned an error/limit mid-stream, HTTP 200)`);
    const toolN = turnLog.filter(t => t.stopReason === 'tool_use').length;
    if (toolN) find.push(`${ICON.info} ${toolN}/${n} turns ended in tool_use (multi-step / agentic round-trips)`);
    const shares = col('thinkingShare');
    if (shares.length) { const avg = shares.reduce((a, b) => a + b, 0) / shares.length; if (avg >= 0.5) find.push(`${ICON.info} reasoning averages ${Math.round(avg * 100)}% of output (thinking-heavy)`); }
    const q = latestQuota();
    if (q) {
      const hot = q.windows.filter(w => w.usedPct != null && w.usedPct >= 80);
      if (hot.length) { hot.forEach(w => find.push(`${ICON.warn} quota ${w.name} at ${w.usedPct}% used${w.resetsInMs > 0 ? ` (resets ${fmtDur(w.resetsInMs)})` : ''}`)); rec.push('Approaching a usage-window limit — pace requests or switch model until it resets.'); }
      else find.push(`${ICON.info} quota: ${fmtQuotaLine(q)}`);
      if (q.overageDisabledReason) find.push(`${ICON.info} overage disabled (${q.overageDisabledReason}) — requests are blocked at 100%, not billed past it`);
    }
    const sm = window._claudeDebug.summary;
    if (sm.chatMs > 0) find.push(`${ICON.info} chat span ${fmtDur(sm.chatMs)} — generated ${fmtDur(sm.engagedMs)} (${Math.round(100 * sm.engagedMs / sm.chatMs)}%), idle ${fmtDur(Math.max(0, sm.chatMs - sm.engagedMs))}`);

    // Build the verdict ONCE, then render it to both the console and the HUD
    // (mirrors reportProbe — no second assembly pass that can drift out of sync).
    const baseline = `total med ${fmtMs(medTotal)} / p90 ${fmtMs(p90Total)} · TTFT med ${fmtMs(sTtft ? sTtft.median : null)} · ${n} turns`;
    const recLines = rec.length ? rec.map(r => '→ ' + r) : ['→ Nothing notable — efficient relative to this session.'];
    const note = 'Note: session-relative ("typical" = this session, not a global baseline); signals are correlations, not proof.';
    const status = find.some(f => f.startsWith(ICON.fail)) ? 'fail' : find.some(f => f.startsWith(ICON.warn)) ? 'warn' : 'ok';

    console.group('🧭 Assessment (relative to THIS session)');
    console.log('baseline:', baseline);
    console.group('findings'); find.forEach(f => console.log(f)); console.groupEnd();
    console.group('recommendations'); recLines.forEach(r => console.log(r)); console.groupEnd();
    console.log(note);
    console.groupEnd();

    renderResultHud('💡 Assessment (this session)', status, ['baseline: ' + baseline, ...find, ...recLines, note]);
  }

  // ─── Fetch interceptor ────────────────────────────────────────────────────────
  window.fetch = async function (...args) {
    const input = args[0];
    const init = args[1];

    const url = input instanceof Request ? input.url
      : (typeof URL !== 'undefined' && input instanceof URL) ? input.href
      : typeof input === 'string' ? input
      : (input && typeof input === 'object' && 'url' in input) ? input.url
      : String(input);
    const method = String(
      init?.method ?? (input instanceof Request ? input.method : undefined) ?? 'GET'
    ).toUpperCase();

    if (!isMonitoredApi(url)) return origFetch.apply(window, args);

    const id = ++reqCounter;
    const conv = convOf(url);
    noteOrg(url);
    endpointCounts.set(endpointKey(url), (endpointCounts.get(endpointKey(url)) || 0) + 1);
    const t0 = performance.now();
    const stack = captureCallers ? callerStack() : null;   // off by default (perf); enable via _claudeDebug.callers()

    // Grab the Request-body clone synchronously (inside analyzeBody) BEFORE the
    // fetch is dispatched, then dispatch immediately so we add no latency.
    const bodyInfoP = analyzeBody(input, init);
    const responseP = origFetch.apply(window, args);
    responseP.catch(() => {});   // mark handled; real error path is the await below

    pendingRequests.set(id, { id, url, method, start: t0 });
    maxInFlight = Math.max(maxInFlight, pendingRequests.size);

    let heartbeat = null;
    try {
      const { reqBytes, estInputTokens, inChars, attachments, topKeys, inputApprox, meta } = await bodyInfoP;
      const isCompletion = COMPLETION_RE.test(url);
      const isRetry = RETRY_RE.test(url);
      const completionSeq = (isCompletion && !isRetry) ? ++completionCounter : null;   // Nth FRESH completion this session (retries excluded; null for non-completion calls)

      console.groupCollapsed(`[REQ #${id}] ${method} ${url}`);
      console.log('  time:    ', new Date().toISOString());
      if (conv) console.log('  conv:    ', conv);
      console.log('  request: ', `${fmtBytes(reqBytes)}  ~${fmtTok(estInputTokens)} (est)` +
        (attachments ? `  +${attachments} attachment(s) [not token-counted]` : ''));
      if (stack) console.log('  caller:  ', stack);
      console.log('  pending: ', pendingRequests.size, 'requests in flight');
      console.groupEnd();

      heartbeat = setInterval(() => {
        if (!pendingRequests.has(id)) return;
        const elapsed = performance.now() - t0;
        const warnAt = SLOW_ENDPOINT_RE.test(url) ? HANG_SLOW_WARN_MS : HANG_WARN_MS;
        if (elapsed < warnAt) return;   // slow-by-nature endpoints get a longer leash
        console.warn(`[HANG #${id}] still pending after ${(elapsed / 1000).toFixed(1)}s — ${url}`);
      }, HANG_INTERVAL_MS);

      const response = await responseP;
      clearInterval(heartbeat);
      pendingRequests.delete(id);

      const elapsed = performance.now() - t0;
      statusCounts.set(response.status, (statusCounts.get(response.status) || 0) + 1);
      console[response.ok ? 'log' : 'warn'](
        `[RES #${id}] ${response.status} ${response.statusText} ← ${url} (${Math.round(elapsed)}ms)`);

      // Capture ALL response headers once (collapsed), plus parsed Server-Timing
      // and any rate-limit headers (closest keyless proxy for remaining capacity).
      const hdrs = {};
      response.headers.forEach((v, k) => { hdrs[k] = v; });
      console.groupCollapsed(`[RES #${id}] headers`);
      console.log(hdrs);
      const serverTiming = response.headers.get('server-timing');
      if (serverTiming) console.log('server-timing:', parseServerTiming(serverTiming));
      const rl = captureRateLimit(response.headers);
      if (rl) { lastRateLimit = { ...rl, at: Date.now() }; console.log('rate-limit:', rl); }
      console.groupEnd();

      const contentType = response.headers.get('content-type');

      if (response.body && contentType && contentType.includes('text/event-stream')) {
        console.log(`[SSE #${id}] stream opened — decoding events`);
        const monitor = response.clone();

        (async () => {
          let t1 = null;          // first network chunk
          let tEvt = null;        // first decoded content event
          let reads = 0, events = 0, answerChars = 0, thinkingChars = 0, streamBytes = 0;
          let tFirstText = null, tFirstThink = null;   // first answer delta / first thinking delta
          let stopReason = null, stopDetails = null, messageLimit = null, streamError = null, compaction = null;
          let recorded = false;
          let lastActivity = performance.now();
          // Real usage from the stream IF present. NOTE: claude.ai's internal completion
          // stream omits usage, so on claude.ai these stay null (heuristic is used); the
          // public Anthropic API does send it.
          let realIn = null, realOut = null, cacheRead = null, cacheCreate = null;
          const noteUsage = u => {
            if (!u) return;
            if (Number.isFinite(u.input_tokens)) realIn = u.input_tokens;
            if (Number.isFinite(u.output_tokens)) realOut = u.output_tokens;
            if (Number.isFinite(u.cache_read_input_tokens)) cacheRead = u.cache_read_input_tokens;
            if (Number.isFinite(u.cache_creation_input_tokens)) cacheCreate = u.cache_creation_input_tokens;
          };
          const noteLimit = o => {               // capture a claude.ai message_limit event
            if (!o || typeof o !== 'object') return;
            // the payload usually lives in a nested `message_limit` object (quota/reset);
            // keep it whole when present, else fall back to top-level scalar fields.
            if (o.message_limit && typeof o.message_limit === 'object') { messageLimit = o.message_limit; return; }
            const out = {};
            for (const k in o) { const v = o[k]; if (v == null || typeof v !== 'object') out[k] = v; }
            messageLimit = out;
          };
          // One place to absorb an event: usage, stop reason, message_limit, content sizing.
          const ingest = obj => {
            const t = obj.type;
            if (t !== 'content_block_delta') {   // usage/stop/limit/error never ride content deltas (the hot path)
              noteUsage(usageFromEvent(obj));
              const sr = (obj.delta && obj.delta.stop_reason) || obj.stop_reason;
              if (sr) { stopReason = sr; stopDetails = (obj.delta && obj.delta.stop_details) || obj.stop_details || stopDetails; }
              if (t === 'message_limit') noteLimit(obj);
              if (t === 'error') streamError = obj.error || obj;   // claude.ai delivers errors as an SSE event (HTTP 200)
              if (t === 'compaction_status') compaction = obj.compaction_status || obj;   // context-compaction signal
            }
            const n = outputCharsFromEvent(obj);   // signed: + answer, - thinking, 0 none
            if (n > 0) answerChars += n;
            else if (n < 0) thinkingChars -= n;
            return n;                              // signed: caller derives first-answer vs first-thinking
          };
          // Inter-event gaps (ms) for throughput jitter.
          const gaps = []; let lastEventTs = null;
          // Schema-probe accumulators (only when armed; latch so one turn consumes it).
          const probing = probeArmed; if (probing) probeArmed = false;
          const probe = probing ? { topKeys: new Set(), deltaKeys: new Set(), types: new Set(), usageFields: new Set(), limitKeys: new Set(), known: false, unknown: false, sawError: false, errorType: null, samples: 0 } : null;
          const reader = monitor.body.getReader();
          const decoder = new TextDecoder();
          let buf = '';

          const finish = (status, t2) => {
            if (recorded) return;
            recorded = true;
            clearInterval(watchdog);
            const streamDuration = t1 != null ? Math.round(t2 - t1) : null;
            const outChars = answerChars + thinkingChars;
            const estOutputTokens = estimateTokens(outChars);
            // Prefer real usage from the stream when present; fall back to heuristic.
            const inputTokens  = realIn  != null ? realIn  : estInputTokens;
            const outputTokens = realOut != null ? realOut : estOutputTokens;
            const tokensReal   = realIn != null || realOut != null;
            // Self-calibrate chars/token from this turn's real input (future heuristic turns).
            if (realIn != null && realIn > 0 && Number.isFinite(inChars) && inChars > 0) {
              calChars += inChars; calTokens += realIn;
            }
            const total = Math.round(t2 - t0);
            const answerTok = estimateTokens(answerChars);
            const thinkingShare = (answerChars + thinkingChars) > 0
              ? +(thinkingChars / (answerChars + thinkingChars)).toFixed(2) : null;
            const answerTokPerSec = (streamDuration && streamDuration > 0 && answerChars > 0)
              ? Math.round(answerTok / (streamDuration / 1000)) : null;     // perceived (answer-only) rate
            const reasonedMs = (tFirstText != null && tFirstThink != null)
              ? Math.round(tFirstText - tFirstThink) : null;                // ms reasoning before first answer
            if (streamError) streamErrorCount++;
            const tokPerSec = (streamDuration && streamDuration > 0 && outputTokens != null)
              ? Math.round(outputTokens / (streamDuration / 1000)) : null;   // steady (excl. TTFT)
            const tokPerSecWall = (total > 0 && outputTokens != null)
              ? Math.round(outputTokens / (total / 1000)) : null;            // wall (incl. TTFT)
            const gapSorted = gaps.length ? [...gaps].sort((a, b) => a - b) : [];
            const ep = pathOf(url).split('/').pop() || '';
            recordTurn({
              id, conv, url, endpoint: ep, isCompletion, isRetry, via: 'fetch', t0, t1, t2,
              ttft:      t1   != null ? Math.round(t1 - t0)   : null,
              ttftEvent: tEvt != null ? Math.round(tEvt - t0) : null,
              streamDuration, total,
              reads, events, reqBytes, inChars, attachments,
              estInputTokens, estOutputTokens,
              inputTokens, outputTokens, tokensReal,
              cacheRead, cacheCreate,
              streamBytes, tokPerSec, tokPerSecWall,
              interEventP50: gapSorted.length ? Math.round(quantile(gapSorted, 0.5))  : null,
              interEventP95: gapSorted.length ? Math.round(quantile(gapSorted, 0.95)) : null,
              answerChars, thinkingChars,
              ttftText: tFirstText != null ? Math.round(tFirstText - t0) : null,
              ttftThink: tFirstThink != null ? Math.round(tFirstThink - t0) : null,
              reasonedMs, thinkingShare, answerTok, answerTokPerSec,
              stopReason, stopDetails, messageLimit, streamError, compaction,
              model: meta.model, thinkingMode: meta.thinkingMode, effort: meta.effort,
              toolCount: meta.toolCount, attachmentCount: meta.attachmentCount, syncSources: meta.syncSources,
              inputApprox,
              status,
            });
            if (probing) reportProbe({
              id, completionSeq, url, conv, endpoint: ep, isCompletion,
              reqParsedKeys: topKeys, inChars, attachments, probe, meta, inputApprox,
            });
          };

          const watchdog = setInterval(() => {
            const idle = performance.now() - lastActivity;
            if (idle > STREAM_MAX_IDLE_MS) {
              console.error(`[SSE STALL #${id}] no data for ${(idle / 1000).toFixed(0)}s — releasing monitor reader`);
              reader.cancel().catch(() => {});
              finish(`${response.status} (stalled — released after ${Math.round(idle)}ms idle)`, performance.now());
            } else if (idle > STREAM_STALL_MS) {
              console.warn(`[SSE STALL #${id}] no chunk for ${(idle / 1000).toFixed(1)}s (${events} events so far) — stream may be stuck`);
            }
          }, STALL_CHECK_MS);

          try {
            while (true) {
              const { value, done } = await reader.read();
              if (done) {
                const t2 = performance.now();
                // Flush buffered final line (Anthropic ends with \n\n, but be safe).
                buf += decoder.decode();
                if (buf.startsWith('data:')) {
                  const payload = buf.slice(5).trim();
                  if (payload && payload !== '[DONE]') {
                    const obj = tryParse(payload);
                    if (obj && !isPingEvent(obj)) {   // skip truncated / unparseable trailing line
                      if (probe) collectProbe(probe, obj);
                      ingest(obj);
                    }
                  }
                }
                if (!recorded) {
                  const haveReal = realIn != null || realOut != null;
                  const outTok = realOut != null ? realOut : estimateTokens(answerChars + thinkingChars);
                  console.log(`[SSE #${id}] closed cleanly — ${events} events, ${haveReal ? '' : '~'}${fmtTok(outTok)} out ${haveReal ? '(API)' : '(est)'}, ${((t2 - t0) / 1000).toFixed(2)}s`);
                }
                finish(response.status, t2);
                break;
              }
              reads++;
              if (t1 == null) {
                t1 = performance.now();
                console.log(`[SSE #${id}] first chunk after ${Math.round(t1 - t0)}ms (≈ network TTFT)`);
              }
              lastActivity = performance.now();
              if (value) {
                streamBytes += value.byteLength || 0;
                buf += decoder.decode(value, { stream: true });
                let nl, from = 0;
                while ((nl = buf.indexOf('\n', from)) >= 0) {
                  const line = buf.slice(from, nl);
                  from = nl + 1;
                  if (line.startsWith('data:')) {
                    const payload = line.slice(5).trim();
                    if (!payload || payload === '[DONE]') continue;
                    const obj = tryParse(payload);
                    if (probe && obj) collectProbe(probe, obj);
                    if (isPingEvent(obj)) continue;        // keep-alive, not content
                    const now = performance.now();
                    if (tEvt == null) tEvt = now;
                    else gaps.push(now - lastEventTs);
                    lastEventTs = now;
                    events++;
                    const n = ingest(obj);
                    if (n > 0 && tFirstText == null) tFirstText = now;
                    else if (n < 0 && tFirstThink == null) tFirstThink = now;
                  }
                }
                if (from) buf = buf.slice(from);   // drop consumed prefix once per chunk
              }
            }
          } catch (e) {
            console.error(`[SSE #${id}] stream error after ${events} events: ${e.message}`);
            finish(`${response.status} (stream error: ${e.message})`, performance.now());
          }
        })();
      } else if (USAGE_RE.test(url) && contentType && contentType.includes('application/json')) {
        // No-key subscription signal: the web app already fetched this; read the
        // plan tier and any rolling-window quota from a CLONE (page body untouched).
        response.clone().json()
          .then(j => { notePlanFromJson(j); if (!noteUsageEndpoint(j)) { const ml = findMessageLimit(j); if (ml) persistQuota(ml); } })
          .catch(() => {});
      }

      return response; // original, untouched

    } catch (err) {
      clearInterval(heartbeat);
      pendingRequests.delete(id);
      failCount++;
      console.error(`[FAIL #${id}] ${method} ${url}`);
      console.error('  error:  ', err.message);
      console.error('  type:   ', err.name);
      console.error('  elapsed:', `${Math.round(performance.now() - t0)}ms`);
      console.error('  caller: ', stack);
      throw err;
    }
  };

  // ─── WebSocket monitor ────────────────────────────────────────────────────────
  // claude.ai is fetch/SSE today, but if any traffic moves to WebSocket this keeps
  // it visible. Scoped to monitored hosts; counts sent/received frames.
  function MonitoredWebSocket(url, protocols) {
    const ws = protocols !== undefined ? new origWebSocket(url, protocols) : new origWebSocket(url);
    try {
      const host = new URL(url, location.href).hostname;
      if (isMonitoredHost(host)) {
        const rec = { url: String(url), opened: Date.now(), closed: null, sent: 0, recv: 0 };
        wsLog.push(rec);
        if (wsLog.length > MAX_SOCKETS) wsLog.shift();
        console.log(`[WS] open ${url}`);
        ws.addEventListener('message', () => { rec.recv++; });
        ws.addEventListener('close', () => {
          rec.closed = Date.now();
          console.log(`[WS] close ${url} (recv ${rec.recv}, sent ${rec.sent})`);
        });
        const origSend = ws.send.bind(ws);
        ws.send = function (...a) { rec.sent++; return origSend(...a); };
      }
    } catch { /* leave the socket untouched on any parsing error */ }
    return ws;
  }
  MonitoredWebSocket.prototype = origWebSocket.prototype;
  for (const k of ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED']) MonitoredWebSocket[k] = origWebSocket[k];
  window.WebSocket = MonitoredWebSocket;

  // ─── XMLHttpRequest monitor ───────────────────────────────────────────────────
  // Safety net for the fetch blind spot: anything claude.ai sends via XHR (now or
  // after a future migration) would otherwise be invisible. We time monitored
  // /api/ calls and, for SSE-style responses, record a turn by parsing the
  // progressive responseText. CONTENT IS MEASURED, NOT LOGGED.
  const origXhrOpen = origXHR.prototype.open;
  const origXhrSend = origXHR.prototype.send;
  function installXhrMonitor() {
    origXHR.prototype.open = function (method, url, ...rest) {
      this.__cdMethod = String(method || 'GET').toUpperCase();
      this.__cdUrl = url;
      return origXhrOpen.call(this, method, url, ...rest);
    };
    origXHR.prototype.send = function (body) {
      const url = this.__cdUrl;
      if (!url || !isMonitoredApi(url)) return origXhrSend.call(this, body);

      const id = ++reqCounter;
      const conv = convOf(url);
      noteOrg(url);
      endpointCounts.set(endpointKey(url), (endpointCounts.get(endpointKey(url)) || 0) + 1);
      const t0 = performance.now();
      const isCompletion = COMPLETION_RE.test(url);
      const isRetry = RETRY_RE.test(url);
      const reqBytes = typeof body === 'string' ? byteLen(body) : null;
      const parsedBody = typeof body === 'string' ? tryParse(body) : null;
      const inChars = typeof body === 'string'
        ? (parsedBody ? extractStringChars(parsedBody, { attachments: 0 }) : body.length) : null;
      const estInputTokens = inChars != null ? estimateTokens(inChars) : null;
      const meta = requestMeta(parsedBody);

      pendingRequests.set(id, { id, url, method: this.__cdMethod, start: t0 });
      maxInFlight = Math.max(maxInFlight, pendingRequests.size);

      let t1 = null, tEvt = null, lastLen = 0, events = 0, answerChars = 0, thinkingChars = 0;
      let stopReason = null, messageLimit = null, streamError = null, recorded = false;
      let realIn = null, realOut = null, cacheRead = null, cacheCreate = null;

      // Parse only the bytes that arrived since the last progress tick (XHR keeps
      // the full responseText, so we slice forward — no re-parsing).
      const parseForward = txt => {
        if (typeof txt !== 'string' || txt.length <= lastLen) return;
        const slice = txt.slice(lastLen); lastLen = txt.length;
        let from = 0, nl;
        while ((nl = slice.indexOf('\n', from)) >= 0) {
          const line = slice.slice(from, nl); from = nl + 1;
          if (!line.startsWith('data:')) continue;
          const payload = line.slice(5).trim();
          if (!payload || payload === '[DONE]') continue;
          const obj = tryParse(payload);
          if (!obj || isPingEvent(obj)) continue;
          if (tEvt == null) tEvt = performance.now();
          events++;
          const u = usageFromEvent(obj);
          if (u) {
            if (Number.isFinite(u.input_tokens)) realIn = u.input_tokens;
            if (Number.isFinite(u.output_tokens)) realOut = u.output_tokens;
            if (Number.isFinite(u.cache_read_input_tokens)) cacheRead = u.cache_read_input_tokens;
            if (Number.isFinite(u.cache_creation_input_tokens)) cacheCreate = u.cache_creation_input_tokens;
          }
          const sr = (obj.delta && obj.delta.stop_reason) || obj.stop_reason;
          if (sr) stopReason = sr;
          if (obj.type === 'message_limit') messageLimit = (obj.message_limit && typeof obj.message_limit === 'object') ? obj.message_limit : obj;
          if (obj.type === 'error') streamError = obj.error || obj;
          const n = outputCharsFromEvent(obj);
          if (n > 0) answerChars += n; else if (n < 0) thinkingChars -= n;
        }
      };

      const finishXhr = status => {
        if (recorded) return;
        recorded = true;
        clearInterval(hb);
        pendingRequests.delete(id);
        const t2 = performance.now();
        statusCounts.set(status, (statusCounts.get(status) || 0) + 1);
        const outChars = answerChars + thinkingChars;
        const estOutputTokens = estimateTokens(outChars);
        const inputTokens  = realIn  != null ? realIn  : estInputTokens;
        const outputTokens = realOut != null ? realOut : estOutputTokens;
        const tokensReal   = realIn != null || realOut != null;
        if (realIn != null && realIn > 0 && Number.isFinite(inChars) && inChars > 0) { calChars += inChars; calTokens += realIn; }
        if (streamError) streamErrorCount++;
        const total = Math.round(t2 - t0);
        const streamDuration = t1 != null ? Math.round(t2 - t1) : null;
        const ep = pathOf(url).split('/').pop() || '';
        recordTurn({
          id, conv, url, endpoint: ep, isCompletion, isRetry, via: 'xhr', t0, t1, t2,
          ttft:      t1   != null ? Math.round(t1 - t0)   : null,
          ttftEvent: tEvt != null ? Math.round(tEvt - t0) : null,
          streamDuration, total, reads: 0, events,
          reqBytes, inChars, attachments: 0,
          estInputTokens, estOutputTokens,
          inputTokens, outputTokens, tokensReal,
          cacheRead, cacheCreate, streamBytes: null,
          tokPerSec:     (streamDuration && streamDuration > 0 && outputTokens != null) ? Math.round(outputTokens / (streamDuration / 1000)) : null,
          tokPerSecWall: (total > 0 && outputTokens != null) ? Math.round(outputTokens / (total / 1000)) : null,
          interEventP50: null, interEventP95: null,
          answerChars, thinkingChars,
          ttftText: null, ttftThink: null, reasonedMs: null,
          thinkingShare: (answerChars + thinkingChars) > 0 ? +(thinkingChars / (answerChars + thinkingChars)).toFixed(2) : null,
          answerTok: estimateTokens(answerChars), answerTokPerSec: null,
          stopReason, stopDetails: null, messageLimit, streamError, compaction: null,
          model: meta.model, thinkingMode: meta.thinkingMode, effort: meta.effort,
          toolCount: meta.toolCount, attachmentCount: meta.attachmentCount, syncSources: meta.syncSources,
          inputApprox: true, status,
        });
        // Non-SSE usage/account XHR: read plan + quota, no key needed.
        if (!events && USAGE_RE.test(url)) {
          try { const j = JSON.parse(this.responseText); notePlanFromJson(j); if (!noteUsageEndpoint(j)) { const ml = findMessageLimit(j); if (ml) persistQuota(ml); } } catch (_) {}
        }
      };

      const markTtft = () => { if (t1 == null && this.readyState >= origXHR.LOADING) t1 = performance.now(); };
      this.addEventListener('readystatechange', () => { markTtft(); if (this.readyState === origXHR.LOADING) { try { parseForward(this.responseText); } catch (_) {} } });
      this.addEventListener('progress', () => { markTtft(); try { parseForward(this.responseText); } catch (_) {} });
      this.addEventListener('load',  () => { try { parseForward(this.responseText); } catch (_) {} finishXhr(this.status); });
      this.addEventListener('error', () => { failCount++; finishXhr(0); });
      this.addEventListener('abort', () => finishXhr(this.status || 0));

      const hb = setInterval(() => {
        if (!pendingRequests.has(id)) { clearInterval(hb); return; }
        const elapsed = performance.now() - t0;
        const warnAt = SLOW_ENDPOINT_RE.test(url) ? HANG_SLOW_WARN_MS : HANG_WARN_MS;
        if (elapsed >= warnAt) console.warn(`[HANG #${id}] (xhr) still pending after ${(elapsed / 1000).toFixed(1)}s — ${url}`);
      }, HANG_INTERVAL_MS);

      return origXhrSend.call(this, body);
    };
  }
  installXhrMonitor();

  // ─── Browser-level events ─────────────────────────────────────────────────────
  const onVisibility = () =>
    console.log(`[TAB] visibility → ${document.visibilityState}, pending: ${pendingRequests.size}`);
  const onOnline = () => console.log('[NET] back online');
  const onOffline = () => console.log('[NET] went offline');
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('online', onOnline);
  window.addEventListener('offline', onOffline);

  // ─── Performance Observer: per-request network timing + transfer size ──────────
  let perfObs = null;
  if (window.PerformanceObserver) {
    perfObs = new PerformanceObserver(list => {
      for (const entry of list.getEntries()) {
        if (entry.initiatorType !== 'fetch' || !isMonitoredApi(entry.name)) continue;
        console.log(`[TIMING] ${pathOf(entry.name)}`);
        console.log(
          `  dns: ${Math.round(entry.domainLookupEnd - entry.domainLookupStart)}ms` +
          `  tls: ${Math.round(entry.connectEnd - entry.connectStart)}ms` +
          `  ttfb: ${Math.round(entry.responseStart - entry.requestStart)}ms` +
          `  resp: ${Math.round(entry.responseEnd - entry.responseStart)}ms (incl. streaming)`);
        console.log(
          `  proto: ${entry.nextHopProtocol || '?'}` +
          `  wire: ${fmtBytes(entry.transferSize)}` +
          `  enc: ${fmtBytes(entry.encodedBodySize)}` +
          `  dec: ${fmtBytes(entry.decodedBodySize)}`);
      }
    });
    try { perfObs.observe({ type: 'resource', buffered: true }); }
    catch { perfObs.observe({ entryTypes: ['resource'] }); } // older engines
  }

  // ─── Console helpers ──────────────────────────────────────────────────────────
  window._claudeDebug = {
    pending: () => console.table([...pendingRequests.values()]),
    count: () => console.log(`${pendingRequests.size} requests in flight`),
    stats: () => printStats(),
    histogram: (metric = 'total', buckets = 5) => printHistogram(metric, buckets),
    histogramHud: (metric = 'total') => renderHistHud(metric),
    paceHud: () => renderPaceHud(),
    rates: () => printRates(),
    byConversation: () => byConversation(),
    endpoints: () => {
      if (!endpointCounts.size) { console.log('No monitored requests yet.'); return; }
      const rows = [...endpointCounts.entries()].sort((a, b) => b[1] - a[1]);
      const total = rows.reduce((a, [, c]) => a + c, 0);
      console.group(`🌐 Monitored endpoints (${total} requests over ${endpointCounts.size} paths)`);
      console.table(rows.map(([endpoint, count]) => ({ endpoint, count, pct: `${Math.round(100 * count / total)}%` })));
      console.log('Last path segment per /api/ request (id-like tails folded to "<parent>/:id"). Counts every monitored call, not just completions.');
      console.groupEnd();
    },
    sockets: () => {
      if (!wsLog.length) { console.log('No monitored WebSocket activity.'); return; }
      console.table(wsLog.map(w => ({
        url: w.url, recv: w.recv, sent: w.sent,
        state: w.closed ? 'closed' : 'open',
        openMs: (w.closed || Date.now()) - w.opened,
      })));
    },

    rateLimits: () => {
      if (!lastRateLimit) { console.log('No rate-limit headers seen yet.'); return; }
      console.log('Most recent rate-limit headers:', lastRateLimit);
    },

    // Subscription consumption (no API key): persisted rolling-window quota, the
    // metric Free/Pro/Max are actually metered on. Survives reloads via localStorage.
    quota: () => {
      const w = quotaWindowsSnapshot();
      if (!w.length) { console.log('No message_limit windows captured yet (send a message, or open a usage view).'); return; }
      console.table(w.map(x => ({
        window: x.window,
        used: x.usedPct != null ? `${x.usedPct}%` : '?',
        left: x.usedPct != null ? `${100 - x.usedPct}%` : '?',
        status: x.status || '',
        resetsIn: x.resetsInMs != null ? fmtDur(x.resetsInMs) : '?',
        pace: x.paceMultiplier != null ? `${x.paceMultiplier}x` : '',
        estMinsLeft: x.estMinsLeft != null ? `${x.estMinsLeft}m` : '',
      })));
      console.log('plan:', detectedPlan || 'unknown');
    },
    plan: () => { console.log('Detected plan:', detectedPlan || 'unknown (no usage/account response seen yet)'); return detectedPlan; },

    // Actively fetch /api/organizations/<id>/usage (the exact-quota endpoint the
    // web app uses) and refresh the persisted windows. No key — rides the page's
    // own session cookies. Uses origFetch so it isn't re-instrumented.
    refreshQuota: async () => {
      if (!orgId) { console.log('Org id not seen yet — send a message (or open a chat) first, then retry.'); return null; }
      const j = await fetchUsage();
      if (j && noteUsageEndpoint(j)) window._claudeDebug.quota();
      else console.log('refreshQuota: no active windows in payload (or fetch failed).');
      return j;
    },
    domTurns: () => { const n = domTurnCount(); console.log('Rendered assistant turns (heuristic DOM count):', n, '· completions recorded:', window._claudeDebug.summary.completions); return n; },

    health: () => {
      console.group('\ud83e\ude7a Health');
      console.log('peak in-flight: ', maxInFlight, ' · current:', pendingRequests.size);
      console.log('fetch failures: ', failCount);
      console.log('status counts:  ', Object.fromEntries(statusCounts));
      console.log('plan:           ', detectedPlan || 'unknown');
      { const d = domTurnCount(), c = window._claudeDebug.summary.completions;
        console.log('completions/DOM:', `${c} recorded vs ${d == null ? '?' : d} rendered`,
          (d != null && Math.abs(d - c) > 1) ? '\u26a0 divergence — traffic may be escaping the fetch/XHR patches' : ''); }
      if (lastRateLimit) console.log('last rate-limit:', lastRateLimit);
      console.groupEnd();
    },

    probe: () => runSchemaProbe(),
    calibration: () => {
      console.log(calTokens > 0
        ? `chars/token = ${charsPerToken().toFixed(3)} (calibrated from ${calTokens} real input tokens over ${turnLog.filter(t => t.tokensReal).length} exact turns)`
        : `chars/token = ${EST_CHARS_PER_TOKEN} (uncalibrated — no real-usage turns yet)`);
    },
    time: () => {
      const s = window._claudeDebug.summary;
      const idle = Math.max(0, s.chatMs - s.engagedMs);
      console.group('\u23f1 Time');
      console.log('session (since load): ', fmtDur(s.sessionMs), '\u2014 includes idle/reading');
      console.log('chat (first\u2192last turn):', fmtDur(s.chatMs), `over ${s.turns} turns`);
      console.log('engaged (generating): ', fmtDur(s.engagedMs), s.chatMs ? `(${Math.round(100 * s.engagedMs / s.chatMs)}% of chat)` : '');
      console.log('idle (reading/typing):', fmtDur(idle));
      console.groupEnd();
    },
    assess: () => runAssessment(),
    callers: (on = true) => { captureCallers = !!on; console.log(`Caller-stack capture ${captureCallers ? 'ON' : 'OFF'}.`); return captureCallers; },

    // Toggle the on-page overlay. hud() flips it; hud(true)/hud(false) force it.
    hud: (show) => toggleHud(show),

    turns: () => console.table(turnLog.map(t => ({
      '#': t.id, status: t.status, conv: t.conv || '', ep: t.endpoint || '',
      'TTFT': t.ttft, 'TTFTev': t.ttftEvent, 'stream': t.streamDuration, 'total': t.total,
      'events': t.events, 'in': t.inputTokens, 'out': t.outputTokens,
      'cacheRd': t.cacheRead, 'src': t.tokensReal ? 'API' : '~',
      'think': t.thinkingChars ? estimateTokens(t.thinkingChars) : 0,
      'stop': t.stopReason || '', 'model': t.model || '',
      'tok/s': t.tokPerSec, 'gapP95': t.interEventP95,
    }))),

    report: () => {
      const s = window._claudeDebug.summary;
      console.group('📋 Claude debug summary');
      console.log('turns:          ', s.turns);
      console.log('in flight:      ', s.inFlight);
      console.log('last total:     ', fmtMs(s.lastTotalMs));
      console.log('median total:   ', fmtMs(s.medianTotalMs));
      console.log('p90 total:      ', fmtMs(s.p90TotalMs));
      console.log('median TTFT:    ', fmtMs(s.medianTTFTMs));
      console.log('tokens (in+out):', `${s.tokensTotal}  (${s.exactTurns}/${s.turns} exact, rest ~chars/${charsPerToken().toFixed(2)})`);
      console.log('msgs last 1h:   ', s.msgsLastHour);
      console.log('msgs last 24h:  ', s.msgsLast24h);
      console.groupEnd();
      printRates();
      printHistogram();
      window._claudeDebug.health();
    },

    reset: () => {
      turnLog.length = 0; firstTurnTs = lastTurnTs = null; engagedMs = 0;
      slowP90 = null; slowP90At = 0;
      console.log('Turn log + chat clocks cleared (calibration, health, session clock kept). Use resetAll() to clear everything.');
    },
    resetAll: () => {
      turnLog.length = 0; wsLog.length = 0;
      firstTurnTs = lastTurnTs = null; engagedMs = 0;
      calChars = 0; calTokens = 0;
      maxInFlight = 0; failCount = 0; streamErrorCount = 0; statusCounts.clear(); lastRateLimit = null; slowP90 = null; slowP90At = 0;
      console.log('All counters cleared (turns, sockets, chat clocks, calibration, health). Session clock unchanged.');
    },

    export: () => copyJson(turnLog, `Copied ${turnLog.length} turns to clipboard.`),

    // Compact, paste-ready snapshot for the `hud_audit` workflow: session summary +
    // a slim per-turn array (incl. the new thinking/answer/stop/model fields). Copy
    // it and paste to Claude with the keyword "hud_audit" to track trends over time.
    audit: () => {
      const snapshot = buildAuditSnapshot();
      copyJson(snapshot, `hud_audit snapshot copied (${snapshot.data.length} turns) — paste to Claude with "hud_audit".`);
    },

    // Same snapshot as audit(), but injected straight into the chat composer with
    // the `hud_audit` keyword already prefixed. INJECT-ONLY: it never presses Send,
    // so you review the payload and submit it yourself.
    auditInject: () => {
      const snapshot = buildAuditSnapshot();
      const payload = `hud_audit\n\n${JSON.stringify(snapshot, null, 2)}`;
      injectIntoComposer(payload, `hud_audit snapshot (${snapshot.data.length} turns) injected into the composer — review, then press Send.`);
    },

    help: () => {
      const g = (t, items) => { console.group(t); items.forEach(i => console.log(i)); console.groupEnd(); };
      console.group('%c\ud83d\udee0 _claudeDebug commands', 'font-weight:bold');
      g('Reports', ['report() \u2014 summary + rates + histogram', 'rates() \u2014 1m/5m/1h/24h messages/tokens/bytes', 'byConversation() \u2014 per-conversation totals', 'endpoints() \u2014 per-endpoint request tally', 'turns() \u2014 per-turn table', 'stats() \u2014 TTFT/stream/total min/median/p90/max', 'health() \u2014 in-flight/fails/status', 'rateLimits() \u2014 last rate-limit headers']);
      g('Visuals (on-page)', ['hud() \u2014 toggle overlay', 'histogramHud() \u2014 histogram panel (cycles metric)', 'paceHud() \u2014 pace tachometer (5h pace vs time)', 'histogram(metric?) \u2014 histogram to console']);
      g('Diagnostics', ['probe() \u2014 arm schema probe (\ud83d\udd2c)', 'assess() \u2014 outliers & efficiency (\ud83d\udca1)', 'quota() \u2014 subscription rolling-window usage (no key)', 'refreshQuota() \u2014 actively fetch the exact usage endpoint', 'plan() \u2014 detected tier', 'domTurns() \u2014 DOM vs recorded completion cross-check', 'time() \u2014 session/chat/engaged/idle', 'calibration() \u2014 current chars/token', 'callers(on?) \u2014 toggle per-request caller capture']);
      g('Data', ['data \u2014 turn array (getter)', 'summary \u2014 key metrics (getter)', 'export() \u2014 full turn JSON to clipboard', 'audit() \u2014 compact hud_audit snapshot to clipboard (\ud83e\uddfe)', 'auditInject() \u2014 inject hud_audit snapshot + keyword into the chat box, no send (\ud83d\udce8)', 'pending() \u2014 in-flight requests', 'sockets() \u2014 WebSocket activity']);
      g('Control', ['reset() \u2014 clear turns + chat clocks', 'resetAll() \u2014 clear everything but session clock', 'stop() \u2014 restore fetch/WebSocket, remove overlays']);
      console.groupEnd();
    },

    stop: () => {
      destroyHud();
      destroyResultHud();
      window.fetch = origFetch;
      window.WebSocket = origWebSocket;
      origXHR.prototype.open = origXhrOpen;
      origXHR.prototype.send = origXhrSend;
      perfObs?.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('online', onOnline);
      window.removeEventListener('offline', onOffline);
      window.__claudeDebugMonitor = false;
      console.log('Claude Developer Debug Monitor stopped — original fetch/WebSocket restored.');
    },

    // ── Live-Expression-safe getters (return a value, never log; no parens) ─────
    get data() { return [...turnLog]; },

    get summary() {
      const totals = col('total');
      const ttfts  = col('ttft');
      const st = calcStats(totals);
      const tt = calcStats(ttfts);
      const tokensTotal = turnLog.reduce((a, t) =>
        a + (Number.isFinite(t.inputTokens) ? t.inputTokens : 0)
          + (Number.isFinite(t.outputTokens) ? t.outputTokens : 0), 0);
      const exactTurns = turnLog.filter(t => t.tokensReal).length;
      const now = Date.now();
      const rs = ratesSnapshot();                       // shared (memoized) window buckets
      // "Messages" should mean user-visible turns, so count fresh completions
      // (excludes background SSE and retries), not raw turn rows.
      const winMsgs = label => { const r = rs.find(x => x.window === label); return r ? r.freshCompletions : 0; };
      return {
        turns:         turnLog.length,
        completions:   turnLog.filter(t => t.isCompletion && !t.isRetry).length,
        retries:       turnLog.filter(t => t.isRetry).length,
        nonCompletionStreams: turnLog.filter(t => !t.isCompletion).length,
        inFlight:      pendingRequests.size,
        lastTotalMs:   totals.length ? totals[totals.length - 1] : null,
        medianTotalMs: st ? st.median : null,
        p90TotalMs:    st ? st.p90    : null,
        medianTTFTMs:  tt ? tt.median : null,
        tokensTotal,
        exactTurns,
        tokenSource:   exactTurns > 0 ? 'api' : 'estimated',
        plan:          detectedPlan,
        calChars, calTokens,
        cappedAtMaxTurns: turnLog.length >= MAX_TURNS,
        sessionMs:     now - SESSION_START,
        chatMs:        (firstTurnTs != null && lastTurnTs != null) ? lastTurnTs - firstTurnTs : 0,
        engagedMs,
        msgsLastHour:  winMsgs('1h'),
        msgsLast24h:   winMsgs('24h'),
      };
    },
  };

  // ─── On-page overlay (HUD) ──────────────────────────────────────────────────
  // A small, dismissible panel rendered into the page DOM so the metrics are
  // visible WITHOUT opening DevTools. Styles are set via the CSSOM (el.style.*),
  // which is allowed under claude.ai's CSP; no inline <style>/HTML strings.
  const css = (el, props) => { for (const k in props) el.style[k] = props[k]; };

  function mkBtn(label, title, onClick) {
    const b = document.createElement('button');
    b.textContent = label;
    b.title = title;
    css(b, {
      all: 'unset', cursor: 'pointer', color: '#cdbcff', fontSize: '13px',
      lineHeight: '1', padding: '2px 6px', borderRadius: '4px', marginLeft: '4px',
    });
    b.addEventListener('mouseenter', () => css(b, { background: 'rgba(108,71,255,0.35)' }));
    b.addEventListener('mouseleave', () => css(b, { background: 'transparent' }));
    b.addEventListener('click', (e) => { e.stopPropagation(); onClick(); });
    return b;
  }

  // Drag `el` by `handle`. Clamps to the viewport, switches from right/bottom to
  // left/top anchoring on first move, and sets handle.__dragged so a drag doesn't
  // also fire the header's collapse-on-click. Calls onDrop({left,top}) when moved.
  function makeDraggable(el, handle, onDrop) {
    let sx = 0, sy = 0, ox = 0, oy = 0, active = false;
    const onMove = (e) => {
      if (!active) return;
      let left = ox + (e.clientX - sx), top = oy + (e.clientY - sy);
      left = Math.max(0, Math.min(left, window.innerWidth  - el.offsetWidth));
      top  = Math.max(0, Math.min(top,  window.innerHeight - el.offsetHeight));
      el.style.left = left + 'px'; el.style.top = top + 'px';
      el.style.right = 'auto'; el.style.bottom = 'auto';
      if (Math.abs(e.clientX - sx) + Math.abs(e.clientY - sy) > 4) handle.__dragged = true;
    };
    const onUp = () => {
      if (!active) return;
      active = false;
      document.removeEventListener('pointermove', onMove, true);
      document.removeEventListener('pointerup', onUp, true);
      css(handle, { cursor: 'move' });
      if (handle.__dragged && onDrop) onDrop({ left: parseInt(el.style.left, 10), top: parseInt(el.style.top, 10) });
    };
    handle.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || (e.target && e.target.tagName === 'BUTTON')) return;   // left-drag only; let buttons click
      handle.__dragged = false;
      const r = el.getBoundingClientRect();
      ox = r.left; oy = r.top; sx = e.clientX; sy = e.clientY; active = true;
      css(handle, { cursor: 'grabbing' });
      document.addEventListener('pointermove', onMove, true);
      document.addEventListener('pointerup', onUp, true);
      e.preventDefault();   // no text selection while dragging
    });
  }

  function ensureHud() {
    if (hudRoot) return;
    hudRoot = document.createElement('div');
    css(hudRoot, {
      position: 'fixed', top: '80px', right: '12px', zIndex: '2147483647',
      font: '12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace',
      color: '#fff', background: 'rgba(20,16,38,0.92)', border: '1px solid #6c47ff',
      borderRadius: '8px', boxShadow: '0 4px 16px rgba(0,0,0,0.4)', maxWidth: '340px',
      backdropFilter: 'blur(2px)', userSelect: 'none',
    });

    const header = document.createElement('div');
    css(header, {
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 8px', cursor: 'move', borderBottom: '1px solid rgba(108,71,255,0.4)',
    });
    header.title = 'Drag to move · click title to collapse';
    hudTitle = document.createElement('span');
    css(hudTitle, { fontWeight: 'bold', color: '#cdbcff' });
    const btns = document.createElement('span');
    // Hide/close (×) lives at the FAR LEFT, set apart by a gap, so it is never
    // fat-fingered while toggling expand/collapse (▾) at the far right.
    const closeBtn = mkBtn('×', 'Hide overlay (re-show with _claudeDebug.hud())', () => toggleHud(false));
    css(closeBtn, { marginRight: '10px' });
    btns.appendChild(closeBtn);
    btns.appendChild(mkBtn('\uD83D\uDCCA', 'Show histogram panel (click to cycle metric)', () => {
      const metric = HUD_HIST_METRICS[hudHistIdx % HUD_HIST_METRICS.length];
      hudHistIdx++;
      renderHistHud(metric);
    }));
    btns.appendChild(mkBtn('\uD83C\uDF9B\uFE0F', 'Show pace tachometer (5h pace vs time; red = over 1\u00d7 redline, green = under)', () => renderPaceHud()));
    btns.appendChild(mkBtn('🔬', 'Arm schema probe — analyzes the next turn and reports problems in the console', () => runSchemaProbe()));
    btns.appendChild(mkBtn('💡', 'Assess — outliers, efficiency & recommendations in the console', () => runAssessment()));
    btns.appendChild(mkBtn('⧉', 'Copy turn data as JSON', () => window._claudeDebug.export()));
    btns.appendChild(mkBtn('📨', 'Inject a hud_audit snapshot + keyword into the chat box (review, then press Send yourself)', () => window._claudeDebug.auditInject()));
    btns.appendChild(mkBtn('▾', 'Collapse / expand', () => setCollapsed(!hudCollapsed)));
    header.appendChild(hudTitle);
    header.appendChild(btns);
    header.addEventListener('click', () => { if (header.__dragged) { header.__dragged = false; return; } setCollapsed(!hudCollapsed); });

    hudBody = document.createElement('div');
    css(hudBody, { padding: '8px 8px 4px', whiteSpace: 'pre' });   // aligned rows: no wrap

    hudFoot = document.createElement('div');   // legend is long; give it its own wrapping line
    css(hudFoot, { padding: '0 8px 8px', whiteSpace: 'normal', overflowWrap: 'anywhere',
      color: '#9a8cc8', fontSize: '11px', lineHeight: '1.35' });

    hudRoot.appendChild(header);
    hudRoot.appendChild(hudBody);
    hudRoot.appendChild(hudFoot);
    (document.body || document.documentElement).appendChild(hudRoot);
    if (hudPos == null) hudPos = lsGet('claudeDebugHudPos', null);
    if (hudPos && Number.isFinite(hudPos.left) && Number.isFinite(hudPos.top)) {
      const L = Math.max(0, Math.min(hudPos.left, window.innerWidth  - hudRoot.offsetWidth));
      const T = Math.max(0, Math.min(hudPos.top,  window.innerHeight - hudRoot.offsetHeight));
      css(hudRoot, { left: L + 'px', top: T + 'px', right: 'auto', bottom: 'auto' });
    }
    makeDraggable(hudRoot, header, (pos) => { hudPos = pos; lsSet('claudeDebugHudPos', pos); });
    setCollapsed(hudCollapsed);
  }

  function setCollapsed(collapsed) {
    hudCollapsed = collapsed;
    if (hudBody) hudBody.style.display = collapsed ? 'none' : 'block';
    if (hudFoot) hudFoot.style.display = collapsed ? 'none' : 'block';
    updateHud();
  }

  function updateHud() {
    if (!hudRoot) return;
    if (typeof document !== 'undefined' && document.hidden) return;   // no work in a backgrounded tab
    if (paceRoot) renderPaceHud();   // keep the tachometer live while it's open (independent of collapse)
    if (hudCollapsed) {
      let _tt = 0, _ex = 0;                                           // cheap pill: no sorts, single pass
      for (const _t of turnLog) {
        if (Number.isFinite(_t.inputTokens))  _tt += _t.inputTokens;
        if (Number.isFinite(_t.outputTokens)) _tt += _t.outputTokens;
        if (_t.tokensReal) _ex++;
      }
      const s = { turns: turnLog.length, exactTurns: _ex, tokensTotal: _tt };
      const _pre = s.turns && s.exactTurns === s.turns ? '' : '~';
      const _q5 = quotaWindows['5h'];
      const _q5txt = (_q5 && _q5.usedPct != null) ? ` · 5h ${_q5.usedPct}%` : '';
      hudTitle.textContent = `⏱ ${s.turns} turns · ${_pre}${s.tokensTotal} tok${_q5txt}`;
      return;
    }
    const s = window._claudeDebug.summary;
    const oneH = ratesSnapshot().find(r => r.window === '1h') || { messages: 0, inTokens: 0, outTokens: 0 };
    hudTitle.textContent = 'Claude Debug';
    const oneHTok = oneH.inTokens + oneH.outTokens;

    // Keep the exact /usage windows current while the HUD is open+visible: refresh
    // at most once per QUOTA_POLL_MS (the reset countdowns below tick live every
    // second regardless, since they recompute from the stored reset epoch).
    if (orgId && Date.now() - lastQuotaPollAt > QUOTA_POLL_MS) { lastQuotaPollAt = Date.now(); fetchUsage(); }

    // EXACT subscription usage from /api/.../usage (no key) — its own labelled set
    // of lines, separate from the SSE message_limit block below. 5h and 7d first.
    const usageWins = quotaWindowsSnapshot();
    const usageLines = [];
    if (usageWins.length) {
      const ord = { '5h': 0, '7d': 1 };
      usageWins.sort((a, b) => (ord[a.window] ?? 9) - (ord[b.window] ?? 9) || a.window.localeCompare(b.window));
      usageLines.push('── usage (exact, no key) ──');
      for (const w of usageWins) {
        const reset = (w.resetsInMs != null && w.resetsInMs > 0) ? `resets in ${fmtDur(w.resetsInMs)}` : (w.status || 'reset due');
        const used = w.usedPct != null ? `${w.usedPct}% used` : (w.status || '?');
        usageLines.push(`${w.window}`.padEnd(13) + `${used} · ${reset}`);
        if (w.window === '5h') {
          const p = usagePace('5h');                     // burn rate from the persisted /usage history
          if (p && p.multiplier != null) usageLines.push('5h pace'.padEnd(13) + fmtPace(p));
          if (p && p.estMinsLeft != null) {
            // estMinsLeft is already clamped to the reset; label which event binds.
            const label = p.capBinds ? 'to cap' : 'to reset';
            usageLines.push('5h estMins'.padEnd(13) + `${p.estMinsLeft}m ${label}`);
          } else if (p) {
            usageLines.push('5h estMins'.padEnd(13) + (p.burnPerMin <= 0 ? 'flat/recovering' : 'n/a'));
          }
        }
        if (w.window === '7d') {
          // Same machinery as 5h, but over the 7-day window, and reported in
          // fractional DAYS (2dp) rather than minutes. usagePace() already clamps
          // estMinsLeft = min(minsToCap, minsToReset), so estDays can NEVER exceed
          // the days left before the 7d window resets. Label which event binds,
          // exactly like the 5h estMins line ('to cap' vs 'to reset').
          const p = usagePace('7d');
          if (p && p.multiplier != null) usageLines.push('7d pace'.padEnd(13) + fmtPace(p));
          if (p && p.estMinsLeft != null) {
            const label = p.capBinds ? 'to cap' : 'to reset';
            const estDays = (p.estMinsLeft / 1440).toFixed(2);
            usageLines.push('7d estDays'.padEnd(13) + `${estDays}d ${label}`);
          } else if (p) {
            usageLines.push('7d estDays'.padEnd(13) + (p.burnPerMin <= 0 ? 'flat/recovering' : 'n/a'));
          }
        }
      }
    }

    const _q = latestQuota();
    // Each SSE message_limit window (5h, 7d, …) gets its OWN line, labelled
    // "<window> quota", so a long value never bleeds past the 340px box
    // (whiteSpace:'pre' = no auto-wrap). The overage flag sits on a trailing line.
    const quotaLines = [];
    if (_q) {
      const QPAD = '             ';   // 13 spaces = value column (matches label width)
      for (const w of _q.windows) {
        quotaLines.push(`${w.name} quota`.padEnd(13) + fmtQuotaWindow(w));
        if (w.name === '5h') {
          const p = windowPace('5h');           // rate of 5h utilisation vs clock, last ~10 min
          if (p) quotaLines.push('5h pace'.padEnd(13) + fmtPace(p));
        }
      }
      if (_q.overageInUse) quotaLines.push(`${QPAD}OVERAGE ON`);
      else if (_q.overageDisabledReason) quotaLines.push(`${QPAD}overage off (${_q.overageDisabledReason})`);
    }
    // timeLeft1x = minutes left in the 5h window at a steady 1x (or slower) pace.
    // Anchored to the EXACT reset from /usage (quotaWindows['5h'].resetsAt) so it
    // matches the same clock estMins is clamped to — hence estMins ≤ timeLeft1x holds
    // exactly. Falls back to (5h − session time) only if the endpoint hasn't yet
    // reported a 5h reset. If est is strictly smaller you are burning above 1x (cap
    // sooner) → RED + show estMins; otherwise show timeLeft1x → GREEN. Whole minutes.
    const FIVE_H_MIN = 300;
    const _q5w = quotaWindows['5h'];
    const reset5Min = (_q5w && Number.isFinite(_q5w.resetsAt))
      ? Math.max(0, Math.round((_q5w.resetsAt - Date.now()) / 60000)) : null;
    const timeLeft1x = (reset5Min != null) ? reset5Min : Math.max(0, Math.round(FIVE_H_MIN - s.sessionMs / 60000));
    const _p5 = usagePace('5h');
    const est5 = (_p5 && _p5.estMinsLeft != null) ? _p5.estMinsLeft : null;
    // Split across two lines so the pace annotation never bleeds past the HUD's
    // right edge: line 1 is the value, line 2 is the indented pace note (same colour,
    // aligned under the value column). Applies to both the above-1x and below-1x cases.
    const _ind = ' '.repeat(13);
    let paceLines;
    if (est5 != null && est5 < timeLeft1x) {                  // burning ABOVE 1x -> cap before reset
      paceLines = [
        { t: 'estMins'.padEnd(13) + `${est5}m`,               c: '#ff6b6b' },
        { t: _ind + `above 1\u00d7 pace \u00b7 1\u00d7 left ${timeLeft1x}m`, c: '#ff6b6b' },
      ];
    } else if (est5 != null) {                                // at/below 1x -> reset before cap
      paceLines = [
        { t: 'timeLeft1x'.padEnd(13) + `${timeLeft1x}m`,      c: '#5cdd7b' },
        { t: _ind + `at/below 1\u00d7 pace \u00b7 cap ${est5}m`, c: '#5cdd7b' },
      ];
    } else {                                                  // no pace computed yet
      paceLines = [
        { t: 'timeLeft1x'.padEnd(13) + `${timeLeft1x}m`,      c: '#5cdd7b' },
        { t: _ind + `1\u00d7 runway \u00b7 pace pending`,   c: '#5cdd7b' },
      ];
    }

    const bodyItems = [
      `turns        ${s.turns}   (in-flight ${s.inFlight})`,
      `time         session ${fmtDur(s.sessionMs)} · chat ${fmtDur(s.chatMs)}`,
      `             gen ${fmtDur(s.engagedMs)} / idle ${fmtDur(Math.max(0, s.chatMs - s.engagedMs))}`,
      ...paceLines,
      `total        med ${fmtMs(s.medianTotalMs)} / p90 ${fmtMs(s.p90TotalMs)}`,
      `TTFT         med ${fmtMs(s.medianTTFTMs)}`,
      `tokens       ${s.turns && s.exactTurns === s.turns ? '' : '~'}${s.tokensTotal}  (in+out; ${s.exactTurns}/${s.turns} exact)`,
      `last 1h      ${oneH.messages} msgs · ~${oneHTok} tok`,
      `last 24h     ${s.msgsLast24h} msgs`,
      ...usageLines,
      ...quotaLines,
      `~ / day      ~${oneH.messages * 24} msgs · ~${oneHTok * 24} tok`,
    ];
    // One <div> per line so a single line can be coloured (a joined textContent
    // string can't). Parent is white-space:pre + monospace, so padEnd alignment
    // and leading spaces are preserved; each div's text is set via textContent
    // (no HTML, no escaping concerns). A plain string item is an uncoloured line.
    hudBody.textContent = '';
    for (const it of bodyItems) {
      const ln = (typeof it === 'string') ? { t: it } : it;
      const d = document.createElement('div');
      d.textContent = ln.t;
      if (ln.c) d.style.color = ln.c;
      hudBody.appendChild(d);
    }
    hudFoot.textContent = `~ = est (chars/${charsPerToken().toFixed(2)}); no ~ = exact from stream`;
  }

  // show: undefined = toggle, true = show, false = destroy
  function toggleHud(show) {
    const want = show === undefined ? !hudRoot : !!show;
    if (!want) { destroyHud(); return false; }
    whenBody(() => {
      ensureHud();
      if (!hudInterval) hudInterval = setInterval(updateHud, HUD_REFRESH_MS);
      updateHud();
    });
    return true;
  }

  function destroyHud() {
    if (hudInterval) { clearInterval(hudInterval); hudInterval = null; }
    if (hudRoot && hudRoot.parentNode) hudRoot.parentNode.removeChild(hudRoot);
    hudRoot = hudTitle = hudBody = null;
    destroyHistHud();
  }

  // ── Histogram overlay (second panel) ───────────────────────────
  // Rendered as DOM (CSP-safe via css()), only on click; never auto-refreshes.
  // ─── Shared result panel (probe & assess render here, not just the console) ──
  let resultRoot = null, resultHead = null, resultTitle = null, resultBody = null;
  const RESULT_STATUS = {
    ok:   { bd: '#3fb950', bg: 'rgba(63,185,80,0.18)',  tag: 'PASS'  },
    warn: { bd: '#d29922', bg: 'rgba(210,153,34,0.18)', tag: 'CHECK' },
    fail: { bd: '#f85149', bg: 'rgba(248,81,73,0.18)',  tag: 'FAIL'  },
    info: { bd: '#6c47ff', bg: 'rgba(108,71,255,0.18)', tag: ''      },
  };

  // Shared scaffold for the on-page side panels: a fixed, dark, rounded box with a
  // flex header (title + buttons) and a body. Callers add panel-specific styling
  // and the close button, keeping the two panels visually consistent.
  function makePanel(side) {
    const root = document.createElement('div');
    css(root, {
      position: 'fixed', [side]: '12px', top: '80px', zIndex: '2147483647',
      font: '12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace', color: '#fff',
      background: 'rgba(20,16,38,0.96)', border: '1px solid #6c47ff', borderRadius: '8px',
      boxShadow: '0 4px 16px rgba(0,0,0,0.4)', backdropFilter: 'blur(2px)',
    });
    const head = document.createElement('div');
    css(head, { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px', cursor: 'move' });
    head.title = 'Drag to move';
    const title = document.createElement('span');
    const body = document.createElement('div');
    head.appendChild(title);
    root.appendChild(head);
    root.appendChild(body);
    // Same drag behavior as the main HUD: grab the header to reposition. Buttons
    // the callers add later still click, since makeDraggable ignores BUTTON targets.
    makeDraggable(root, head);
    return { root, head, title, body };
  }

  // Shared panel helpers: position a side panel just below the main HUD (once, at
  // creation, so drags aren't yanked back), and detach a panel from the DOM.
  function placeBelowHud(root) {
    if (root && hudRoot && hudRoot.getBoundingClientRect) {
      const r = hudRoot.getBoundingClientRect();
      if (r.height) root.style.top = Math.round(r.bottom + 8) + 'px';
    }
  }
  function removePanel(root) {
    if (root && root.parentNode) root.parentNode.removeChild(root);
  }

  function ensureResultHud() {
    if (resultRoot) return;
    const p = makePanel('left');
    resultRoot = p.root; resultHead = p.head; resultTitle = p.title; resultBody = p.body;
    css(resultRoot, { maxWidth: '420px', maxHeight: '70vh', overflow: 'auto' });
    css(resultHead, { padding: '6px 10px', fontWeight: 'bold', borderBottom: '1px solid rgba(108,71,255,0.4)' });
    css(resultBody, { padding: '4px 0' });
    resultHead.appendChild(mkBtn('×', 'Close', () => destroyResultHud()));
    (document.body || document.documentElement).appendChild(resultRoot);
  }

  function destroyResultHud() {
    removePanel(resultRoot);
    resultRoot = resultHead = resultTitle = resultBody = null;
  }

  // status: 'ok' | 'warn' | 'fail' | 'info'. lines keep their ✅/⚠️/❌ prefixes.
  function renderResultHud(title, status, lines) {
    whenBody(() => {
      ensureResultHud();
      const c = RESULT_STATUS[status] || RESULT_STATUS.info;
      css(resultRoot, { border: '1px solid ' + c.bd });
      css(resultHead, { background: c.bg });
      resultTitle.textContent = c.tag ? (title + '  —  ' + c.tag) : title;
      while (resultBody.firstChild) resultBody.removeChild(resultBody.firstChild);
      for (const ln of lines) {
        const row = document.createElement('div');
        css(row, { padding: '3px 10px', whiteSpace: 'normal', overflowWrap: 'anywhere',
          borderTop: '1px solid rgba(255,255,255,0.06)' });
        row.textContent = ln;
        resultBody.appendChild(row);
      }
    });
  }

  function ensureHistHud() {
    if (histRoot) return;
    const p = makePanel('right');
    histRoot = p.root; histTitle = p.title; histBody = p.body;
    css(histRoot, { maxWidth: '340px', padding: '8px', userSelect: 'none' });
    css(p.head, { marginBottom: '6px' });
    css(histTitle, { fontWeight: 'bold', color: '#cdbcff' });
    p.head.appendChild(mkBtn('×', 'Close histogram', () => destroyHistHud()));
    (document.body || document.documentElement).appendChild(histRoot);
    // Position once, at creation (so re-renders on metric-cycle don't yank it back
    // after the user has dragged it).
    placeBelowHud(histRoot);
  }

  function destroyHistHud() {
    removePanel(histRoot);
    histRoot = histTitle = histBody = null;
  }

  function renderHistHud(metric) {
    whenBody(() => {
      ensureHistHud();
      const h = histogramData(metric, 5);
      histTitle.textContent = `📊 ${h.label}`;
      while (histBody.firstChild) histBody.removeChild(histBody.firstChild);
      const mk = (txt, props) => { const d = document.createElement('div'); d.textContent = txt; if (props) css(d, props); return d; };
      if (h.note) { histBody.appendChild(mk(h.note, { color: '#cdbcff' })); return; }
      histBody.appendChild(mk(`${h.n} turns`, { color: '#9a86d8', marginBottom: '4px' }));
      if (h.single) { histBody.appendChild(mk(`all ${h.n} turns ≈ ${h.single}`)); return; }
      for (const r of h.rows) {
        const row = document.createElement('div');
        css(row, { display: 'flex', alignItems: 'center', gap: '6px', whiteSpace: 'nowrap', marginTop: '2px' });
        const range = document.createElement('span');
        css(range, { width: '150px', textAlign: 'right', color: '#cdbcff', flex: '0 0 auto' });
        range.textContent = `${r.lo}–${r.hi}`;
        const barWrap = document.createElement('span');
        css(barWrap, { flex: '1 1 auto', minWidth: '120px' });
        const bar = document.createElement('span');
        css(bar, { display: 'inline-block', height: '10px', width: Math.round(r.frac * 120) + 'px',
          background: '#6c47ff', borderRadius: '2px', verticalAlign: 'middle' });
        barWrap.appendChild(bar);
        const cnt = document.createElement('span');
        css(cnt, { width: '24px', textAlign: 'right', flex: '0 0 auto' });
        cnt.textContent = String(r.count);
        row.appendChild(range); row.appendChild(barWrap); row.appendChild(cnt);
        histBody.appendChild(row);
      }
    });
  }

  // ─── Pace tachometer panel (5h pace vs time, SVG) ───────────────────────────
  function ensurePaceHud() {
    if (paceRoot) return;
    const p = makePanel('right');
    paceRoot = p.root; paceTitle = p.title; paceBody = p.body;
    css(paceRoot, { maxWidth: '340px', padding: '8px', userSelect: 'none' });
    css(p.head, { marginBottom: '6px' });
    css(paceTitle, { fontWeight: 'bold', color: '#cdbcff' });
    p.head.appendChild(mkBtn('×', 'Close tachometer', () => destroyPaceHud()));
    (document.body || document.documentElement).appendChild(paceRoot);
    placeBelowHud(paceRoot);   // sit below the main HUD if visible (set once at creation)
  }
  function destroyPaceHud() {
    removePanel(paceRoot);
    paceRoot = paceTitle = paceBody = null;
  }
  function renderPaceHud() {
    whenBody(() => {
      ensurePaceHud();
      const RED = '#f85149', GREEN = '#3fb950', GRID = 'rgba(255,255,255,0.15)', REDLINE = '#d29922';
      const pts = (paceLog['5h'] || []).filter(p => p && Number.isFinite(p.mult));
      paceTitle.textContent = '\uD83C\uDF9B\uFE0F 5h pace \u00b7 tachometer';
      paceBody.innerHTML = '';
      if (pts.length < 2) {
        const d = document.createElement('div');
        d.textContent = 'Revving up\u2026 keep the HUD open; it samples /usage ~1\u00d7/min. Need 2+ points.';
        css(d, { color: '#cdbcff', maxWidth: '300px', whiteSpace: 'normal' });
        paceBody.appendChild(d);
        return;
      }
      // geometry — fixed 0..4x dial (like a real tachometer), so the needle height
      // is comparable across renders and the 1x redline sits at a constant place.
      const WHITE = '#ffffff';
      const W = 312, H = 150, m = { l: 34, r: 10, t: 10, b: 22 };
      const t0 = pts[0].ts, t1 = pts[pts.length - 1].ts, span = Math.max(1, t1 - t0);
      const maxM = 4;
      const X = t => m.l + (W - m.l - m.r) * ((t - t0) / span);
      const Y = v => m.t + (H - m.t - m.b) * (1 - Math.min(Math.max(v, 0), maxM) / maxM);
      let svg = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">`;
      svg += `<line x1="${m.l}" y1="${m.t}" x2="${m.l}" y2="${H - m.b}" stroke="${GRID}"/>`;
      svg += `<line x1="${m.l}" y1="${H - m.b}" x2="${W - m.r}" y2="${H - m.b}" stroke="${GRID}"/>`;
      // y-axis gridlines + labels at the requested marks (1.0 is drawn below as the redline)
      const TICKS = [0, 0.5, 1, 1.5, 2, 3, 4];
      for (const tk of TICKS) {
        const yy = Y(tk);
        if (tk !== 1) svg += `<line x1="${m.l}" y1="${yy.toFixed(1)}" x2="${W - m.r}" y2="${yy.toFixed(1)}" stroke="${GRID}"/>`;
        svg += `<text x="${m.l - 4}" y="${(yy + 3).toFixed(1)}" fill="${WHITE}" font-size="8" text-anchor="end">${tk.toFixed(1)}</text>`;
      }
      // the 1.0x "redline" — prominent (solid amber, thicker) so it reads clearly
      // against the white trace; above it you burn faster than the clock.
      const y1 = Y(1);
      svg += `<line x1="${m.l}" y1="${y1.toFixed(1)}" x2="${W - m.r}" y2="${y1.toFixed(1)}" stroke="${REDLINE}" stroke-width="1.5"/>`;
      svg += `<text x="${W - m.r}" y="${(y1 - 3).toFixed(1)}" fill="${REDLINE}" font-size="9" text-anchor="end">1.0\u00d7 redline</text>`;
      // trace segments coloured by the newer endpoint (over the redline = red,
      // under = green); per-reading dots are coloured the same. y-axis labels are
      // white (set above) so the scale reads clearly against the coloured trace.
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1], b = pts[i], col = b.mult > 1 ? RED : GREEN;
        svg += `<line x1="${X(a.ts).toFixed(1)}" y1="${Y(a.mult).toFixed(1)}" x2="${X(b.ts).toFixed(1)}" y2="${Y(b.mult).toFixed(1)}" stroke="${col}" stroke-width="1.5"/>`;
      }
      for (const p of pts) {
        const col = p.mult > 1 ? RED : GREEN;
        svg += `<circle cx="${X(p.ts).toFixed(1)}" cy="${Y(p.mult).toFixed(1)}" r="2.4" fill="${col}"/>`;
      }
      svg += `</svg>`;
      paceBody.innerHTML = svg;
      // caption: current RPM + plain-language verdict
      const cur = pts[pts.length - 1].mult, spanMin = Math.round(span / 60000);
      const cap = document.createElement('div');
      cap.textContent = `now ${cur.toFixed(2)}\u00d7 \u00b7 ${cur > 1 ? '\uD83D\uDD34 over redline (cap before reset)' : '\uD83D\uDFE2 under 1\u00d7 (reach reset with quota to spare)'} \u00b7 last ${spanMin}m, ${pts.length} pts`;
      css(cap, { marginTop: '4px', fontSize: '11px', color: cur > 1 ? RED : GREEN, whiteSpace: 'normal', maxWidth: '300px' });
      paceBody.appendChild(cap);
    });
  }

  function whenBody(fn) {
    if (document.body) fn();
    else document.addEventListener('DOMContentLoaded', fn, { once: true });
  }

  // Auto-show the overlay (starts collapsed; dismiss with × or _claudeDebug.hud(false)).
  toggleHud(true);

  console.log('%c Claude Developer Debug Monitor active ', 'background:#6c47ff;color:white;font-weight:bold');
  console.log('  _claudeDebug.report()   — summary + usage rates + histogram');
  console.log('  _claudeDebug.hud()      — toggle the on-page overlay (auto-shown, starts collapsed)');
  console.log('  _claudeDebug.rates()    — rolling messages/tokens/bytes (1m/5m/1h/24h)');
  console.log('  _claudeDebug.turns()    — per-turn table (timing + ~tokens + tok/s)');
  console.log('  _claudeDebug.histogram(metric?) — total|ttft|ttftEvent|streamDuration|outputTokens|inputTokens|tokPerSec|tokPerSecWall|interEventP95|cacheRead|reqBytes|streamBytes');
  console.log('  _claudeDebug.probe()    — arm a schema probe; next turn is analyzed for parser/shape problems (also the 🔬 HUD button)');
  console.log('  _claudeDebug.assess()   — outliers, efficiency & recommendations · _claudeDebug.time() — session/chat/engaged time');
  console.log('  _claudeDebug.byConversation(), .sockets(), .health(), .rateLimits(), .histogramHud(), .calibration(), .stats(), .pending(), .export(), .stop()');
  console.log('  _claudeDebug.help()     \u2014 grouped list of every command');
  console.log('%c Live-Expression-safe (👁 button, no parens): _claudeDebug.summary / _claudeDebug.data ', 'color:#6c47ff;font-weight:bold');
  console.log('  Tokens come from the stream usage object when present (exact); otherwise heuristic ~chars/3.6. No API key used.');
})();
EOF

echo "  wrote claude_developer_debug.js"

# ─── package the unpacked folder into a local .zip (+ .xpi) ───────────────────
# Runs on every execution so you always get a distributable archive next to the
# folder. Prefers web-ext (proper MV3 packaging); falls back to `zip`, then to
# python's zipfile, so the archive is produced even without npm/web-ext.
ZIPDIR="web-ext-artifacts"
mkdir -p "$ZIPDIR"
VER="$(grep -o '"version"[^,]*' "$EXTDIR/manifest.json" | grep -o '[0-9][0-9.]*' || true)"
VER="${VER:-1.0}"
ZIP=""
if command -v web-ext >/dev/null 2>&1; then
  echo "  packaging with web-ext..."
  if web-ext build --source-dir "$EXTDIR" --artifacts-dir "$ZIPDIR" --overwrite-dest >/dev/null 2>&1; then
    ZIP="$(ls -t "$ZIPDIR"/*.zip 2>/dev/null | head -1 || true)"
  fi
fi
if [ -z "$ZIP" ]; then
  [ -x "$(command -v web-ext || true)" ] || echo "  web-ext not available — using a plain zip fallback"
  ZIP="$ZIPDIR/claude_developer_debug-${VER}.zip"
  rm -f "$ZIP"
  if command -v zip >/dev/null 2>&1; then
    ( cd "$EXTDIR" && zip -q -r -X "../$ZIP" . )
  else
    python3 - "$EXTDIR" "$ZIP" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
PY
  fi
fi
# an .xpi is just the zip renamed; Firefox's "Install Add-on From File" wants .xpi
XPI="${ZIP%.zip}.xpi"
cp -f "$ZIP" "$XPI"
echo "  built package: $ZIP"
echo "  built package: $XPI  (identical bytes; .xpi is for Firefox file-install)"
echo ""

cat <<INSTR

Done. Unpacked extension ready at: $EXTDIR/
  - manifest.json
  - claude_developer_debug.js

------------------------------------------------------------------------------
INSTALL - CHROME / EDGE (111+)
------------------------------------------------------------------------------
  1. Open  chrome://extensions   (Edge: edge://extensions)
  2. Turn ON "Developer mode" (top-right toggle)
  3. "Load unpacked"  ->  select the  $EXTDIR/  folder
  4. Open or refresh claude.ai - the monitor auto-runs, nothing to paste
  Update after editing the JS: click the reload icon on the card, then
  hard-refresh claude.ai (Cmd/Ctrl+Shift+R).

------------------------------------------------------------------------------
INSTALL - OPERA (Chromium-based; loads this unpacked extension directly)
------------------------------------------------------------------------------
  Opera runs on the same Chromium engine as Chrome, so it loads this unpacked
  Chrome/MV3 extension natively. You do NOT need the "Install Chrome Extensions"
  bridge add-on here — that bridge is only for pulling listings from the Chrome
  Web Store; this is a local unpacked folder, so load it directly:
  1. Open  opera://extensions
  2. Turn ON "Developer mode" (top-right toggle)
  3. "Load unpacked"  ->  select the  $EXTDIR/  folder
  4. Open or refresh claude.ai - the monitor auto-runs, nothing to paste
  Update after editing the JS: click the reload icon on the card, then
  hard-refresh claude.ai (Cmd/Ctrl+Shift+R).
  (Opera also needs to be new enough for "world":"MAIN" content scripts — any
  Opera built on Chromium 111+; current Opera is well past that.)
  Note: Opera CANNOT run Firefox (.xpi) add-ons; the Firefox paths below do not
  apply to it.

------------------------------------------------------------------------------
INSTALL - FIREFOX, TEMPORARY (any Firefox 128+, wiped on restart)
------------------------------------------------------------------------------
  1. Open  about:debugging  ->  "This Firefox"
  2. "Load Temporary Add-on..."  ->  select  $EXTDIR/manifest.json
  Disappears when Firefox closes. Fine for a quick look; NOT persistent.

------------------------------------------------------------------------------
INSTALL - FIREFOX, PERSISTENT (survives restarts)
------------------------------------------------------------------------------
  This script ALREADY built the package locally (above):
      $ZIPDIR/claude_developer_debug-<ver>.zip   and   ...-<ver>.xpi
  But Release/Beta Firefox REFUSE unsigned add-ons for permanent install, so that
  bare .xpi will not stick on stock Firefox. Pick ONE path:

  PATH A - Self-sign via Mozilla AMO  (works on ALL Firefox, recommended)
    cd $EXTDIR
    # one-time: create API credentials at
    #   https://addons.mozilla.org/developers/addon/api/key/
    web-ext sign --channel=unlisted --api-key=YOUR_JWT_ISSUER --api-secret=YOUR_JWT_SECRET
    # produces a SIGNED .xpi in web-ext-artifacts/  (channel=unlisted keeps it
    # private to you - it is not published to the public AMO listing)
    Then in Firefox:  about:addons  ->  gear icon  ->  "Install Add-on From File..."
    ->  pick that signed .xpi.

  PATH B - Disable signature enforcement  (Developer Edition / Nightly / ESR ONLY)
    In  about:config  set  xpinstall.signatures.required = false
        (stock Release/Beta IGNORE this pref - Dev/Nightly/ESR only)
    Then  about:addons  ->  gear icon  ->  "Install Add-on From File..."
    ->  pick the  $ZIPDIR/claude_developer_debug-<ver>.xpi  this script just built.
  An .xpi is just the .zip renamed; Firefox's file installer wants the .xpi name.

------------------------------------------------------------------------------
VERIFY IT WORKS
------------------------------------------------------------------------------
  Open claude.ai  ->  DevTools (F12)  ->  Console: a purple
  "Claude Developer Debug Monitor active" banner appears with nothing pasted.
  Send 2+ messages, then either:
    - click the HUD's  the inject button  to drop a hud_audit snapshot into the
      chat box (review, then Send), or
    - run  _claudeDebug.report()  /  _claudeDebug.help()  from the > prompt.

  No banner? Check: extension enabled with no errors; you selected the folder
  CONTAINING manifest.json; browser is new enough (Chrome 111+ / Firefox 128+);
  hard-refresh claude.ai.

INSTR
