# `_claudeDebug` — Everything We Learned Building It

A field guide to the claude.ai network/latency/usage monitor: what it does, why
it's built the way it is, the constraints that shaped it, and the mistakes that
cost us time. Source: `claude_developer_debug.js`, generated/installed by
`claude_browser_extension.sh`. This doc is meant to be complete enough to
**recreate both files from scratch**.

---

## 1. What it is

A MAIN-world content script injected into `https://claude.ai/*` that wraps
`window.fetch` (and `window.WebSocket`) and instruments claude.ai's own API
traffic. For every monitored request it logs `[REQ]` (request size + estimated
input tokens), then `[RES]` (status, elapsed, **all** response headers, parsed
`Server-Timing`, and any rate-limit headers), and for streaming responses a
decoded `[SSE]` lifecycle: it parses the event stream, counts content events,
reads a **real `usage` object when the stream exposes one** (falling back to a
heuristic otherwise), estimates output tokens and throughput, measures
inter-event jitter, and records the turn's timings (first-chunk TTFT, first-event
TTFT, streaming duration, total). It exposes console helpers, an ASCII histogram,
a DOM histogram panel, a rolling rate view, per-conversation totals, a health
summary (peak concurrency / failures / status mix / last rate-limit), session/chat
time, a schema probe that verifies the parser still matches claude.ai's live
shapes, and an assessment that flags outliers and efficiency issues.

It runs **entirely client-side with no API key**. Token figures are **exact when
the stream reports usage**, otherwise **heuristic estimates** (≈ chars / 3.6; see
§4) — useful for usage *rates*, not for billing.

---

## 2. The lessons that actually mattered

### 2.1 Content scripts run in the ISOLATED world by default — that breaks fetch patching
The original bug. An extension content script defaults to an **isolated world**:
a separate JS context that shares the DOM but **not** the page's `window`.
Patching `window.fetch` there patches a different `fetch` than claude.ai calls,
so you see nothing.

**Fix:** declare `"world": "MAIN"` so the script runs in the page's realm, where
`window.fetch` is the real one. It's also what makes `_claudeDebug` reachable
from the page console.

```json
{
  "manifest_version": 3,
  "name": "Claude Developer Debug",
  "version": "1.2",
  "content_scripts": [
    {
      "matches": ["https://claude.ai/*"],
      "js": ["claude_developer_debug.js"],
      "run_at": "document_start",
      "world": "MAIN"
    }
  ]
}
```

- `"run_at": "document_start"` wraps `fetch` **before** the app captures its own
  reference, so even the first request is caught.
- Requires **Chrome 111+ / Firefox 128+**.

### 2.2 MAIN world means the page's CSP governs your code
Running in the page realm means claude.ai's **CSP** applies. Its `script-src`
omits `'unsafe-eval'`, so `eval(...)`, `new Function(...)`, and the **string**
forms `setTimeout("…")` / `setInterval("…")` all throw. The **function** forms
are fine — and that's all the monitor uses. Rules for edits: timers stay function
references, never build code from strings, parse with `JSON.parse`, and build the
overlay/histogram panel with `document.createElement` + `el.style.*` (no inline
HTML or `<style>`). If you ever needed eval, the escape hatch is an isolated-world
script + `postMessage`.

### 2.3 Clone the response; never tee-and-reconstruct
Read a `response.clone()` for monitoring and return the **original** to the page.
An earlier version used `body.tee()` + `new Response(...)`, which dropped `url`,
`type`, `redirected`, and real headers. Guard `response.body === null` (e.g. 204)
before cloning. Caveat: a clone buffers the unread remainder if the two readers
diverge — the watchdog (§2.5) bounds that.

### 2.4 Decode the stream — count events and **target the content**
The old loop did `const { done } = await reader.read()` and **discarded the
bytes**, so "chunks" was just `reader.read()` resolutions. Now the loop keeps
`value`, pushes it through a `TextDecoder` (with a final `decoder.decode()` flush
and a trailing-line parse at `done`), buffers by line, and parses SSE `data:`
framing. Two refinements that matter for accuracy:

- **`[DONE]` and `ping` events are not counted** as content events (an `event:
  ping` keep-alive carries a `data:` line; so does `[DONE]`). Counting them
  inflated the event count and the first-event TTFT.
- **Output sizing targets only the generated text**, via `outputCharsFromEvent()`:
  it reads `delta.text` (text_delta), `delta.partial_json` (tool-use input), or a
  legacy `completion` field — never the event framing (`"type"`,
  `"content_block_delta"`, etc.). Summing *all* string leaves added ~30 framing
  chars on every delta and badly overstated output tokens. **Unknown delta shapes
  fall back** to counting the `delta` object's string leaves only (still skipping
  top-level framing), so an internal schema change degrades gracefully instead of
  silently estimating zero.

### 2.5 The stall watchdog closes a real gap
`pending` is deleted when response **headers** arrive, but an SSE stream can open
then go silent mid-flight. A per-stream watchdog warns `[SSE STALL]` after
`STREAM_STALL_MS` (15s), and after `STREAM_MAX_IDLE_MS` (90s) cancels the
monitor's reader and records the turn as stalled. A `recorded`/`finish()` guard
logs each turn exactly once (clean close, error, or stall).

### 2.6 Size the request body — string **and** Request-object, minus attachments
The outgoing prompt is the richest input signal. `analyzeBody(input, init)` is
async and handles two cases: a string `init.body`, **and** the
`fetch(new Request(...))` case where the body lives on `input` (it takes
`input.clone().text()` synchronously, before the first `await`, so the clone
happens *before* the real fetch consumes the body — the wrapper invokes
`analyzeBody` and then dispatches `origFetch`). It measures byte length and
estimates input tokens from **string content only** (parses JSON, sums string-leaf
chars, ignores keys) and **never logs content**. Crucially, `extractStringChars`
**skips base64/data-URI blobs** (`looksLikeBase64Blob`): an inlined image or file
attachment is thousands of base64 chars, but Claude tokenizes images by *tiles*,
not by base64 length, so counting them as chars/token wildly overstated input.
(Their real bytes still appear in `reqBytes` / transfer sizes.) For a growing
thread, input climbs each turn because the app resends history; measuring the
actual body captures that, where counting only your typed message wouldn't.

### 2.7 Capture response headers — parsed, including rate-limit
The old code read only `content-type`. Now it dumps **every** response header once
per response (collapsed), **parses** `Server-Timing` into `{name:{dur,desc}}`
(`parseServerTiming`), records the HTTP status into a `statusCounts` map, and
extracts any rate-limit headers (`anthropic-ratelimit-*`, `retry-after`,
`x-ratelimit-*`, `ratelimit-*`) into `lastRateLimit` (`captureRateLimit`). Rate-
limit headers are the closest **keyless** proxy for remaining capacity.

### 2.8 Prefer the stream's real `usage` over the heuristic
If the SSE stream exposes a `usage` object (public-API schema: `message_start`
carries `input_tokens` + cache fields, `message_delta` carries running
`output_tokens`), `usageFromEvent` + `noteUsage` capture it and the turn prefers
the **exact** numbers (`tokensReal: true`); otherwise it falls back to the
heuristic. Cache fields (`cache_read_input_tokens`, `cache_creation_input_tokens`)
are recorded too (see §4.2). This is keyless — it only *reads* what the page
already receives. Whether it fires depends on claude.ai's internal stream actually
using that schema; the `turns()` `src` column shows `API` vs `~` so you can tell.

### 2.9 Live Expressions re-evaluate ~4×/sec — keep them side-effect-free
A DevTools **Live Expression** (👁) re-runs several times a second; a *printing*
helper there spams/scrolls the console. Split: printing helpers (`report()`,
`rates()`, `histogram()`, `turns()`, `health()`) run once from the `>` prompt;
value-returning getters (`_claudeDebug.data`, `_claudeDebug.summary`) are safe in
a Live Expression, used **without** parentheses.

### 2.10 Smaller correctness fixes worth keeping
- **`this` pinned to `window`** on the forwarded `origFetch.apply(window, args)` —
  a bare `fetch()` call under `'use strict'` has `this === undefined`, which can
  throw *Illegal invocation* on some engines.
- **URL/method extraction** handles `Request`, `URL`, string, and
  `URLSearchParams`; a `URL` object has `href`, not `url`, so the old `'url' in
  input` check silently dropped `fetch(new URL(...))`.
- **`quantile()`** does linear-interpolation percentiles — a real median for even
  n, and p90 that isn't pinned to `max` on tiny samples.
- **Cross-engine caller stack** (`callerStack`, `STACK_CALLER_FRAMES`): drops the
  V8 `Error` header line if present, then takes the next few frames, instead of a
  fixed V8-only slice. **Off by default** — stack capture is the priciest
  per-request op, so it only runs after `_claudeDebug.callers(true)`.
- `wsLog` is capped at `MAX_SOCKETS`; failures increment `failCount`.

### 2.11 Other hardening worth keeping
IIFE + `'use strict'`; idempotence guard `window.__claudeDebugMonitor` (covers
fetch **and** WebSocket); `performance.now()` for all timing; scoped
`isMonitoredApi` (claude.ai + anthropic.com hosts, `/api/` path) so third-party
RUM is ignored; histogram handles `max === min` and `filter(Number.isFinite)`;
`turnLog` capped at `MAX_TURNS`; a real `stop()` that restores `fetch` **and**
`WebSocket`, disconnects the PerformanceObserver, removes listeners, and tears
down both overlays.

---

## 3. Architecture at a glance

- **Tunables (integer ms unless noted):** `HANG_INTERVAL_MS=5000` (how often a
  still-pending request is *checked*), `HANG_WARN_MS=10000` /
  `HANG_SLOW_WARN_MS=20000` (a `[HANG]` line is logged only once a request passes
  the warn bar — the higher bar applies to slow-by-nature endpoints matched by
  `SLOW_ENDPOINT_RE`, i.e. completion streams and file uploads, so normal multi-
  second TTFT and large uploads stay quiet), `STALL_CHECK_MS=5000`,
  `STREAM_STALL_MS=15000`, `STREAM_MAX_IDLE_MS=90000`, `MAX_TURNS=1000`,
  `MAX_SOCKETS=200`, `BAR_WIDTH=30`, `STACK_CALLER_FRAMES=3`,
  `EST_CHARS_PER_TOKEN=3.6` (token heuristic — English-prose rule of thumb, **not
  exact**), `SLOW_MIN_SAMPLES=10`, `HUD_REFRESH_MS=1000` (overlay refresh; paused while the
  tab is hidden, and the collapsed pill is computed without sorting), `BODY_SCAN_MAX=524288`
  (request bodies larger than this skip the per-leaf token walk and approximate
  input from length — response `usage` overrides it), `SLOW_P90_REFRESH=25`
  (recompute the `[SLOW]` p90 baseline every N turns, not every turn). Plus
  `HUD_HIST_METRICS` (the metric list the 📊 button cycles), `API_HOSTS`,
  `COMPLETION_RE` (matches a chat-completion stream — `.../chat_conversations/<id>/completion`
  and `/retry_completion`; this is what counts as a "message"), `SLOW_ENDPOINT_RE`
  (completion or `upload-file` — the longer HANG leash), and `ASSESS`
  (session-relative assessment thresholds: `slowVsMedian`, `ttftSpike`,
  `inOutRatio`, `ctxGrowth`, `cacheHitLow`, `tpsDip`).
- **State:** `origFetch`, `origWebSocket`, `pendingRequests` (Map),
  `turnLog` (array), `wsLog` (array), `reqCounter`, a shared `TextEncoder`;
  health: `maxInFlight`, `failCount`, `statusCounts` (Map), `lastRateLimit`;
  calibration: `calChars`/`calTokens` (running totals over real-usage turns);
  schema probe: `probeArmed`; time: `SESSION_START`, `firstTurnTs`, `lastTurnTs`,
  `engagedMs`; HUD: `hudRoot/hudTitle/hudBody/hudInterval/hudCollapsed`,
  `hudHistIdx`, and the histogram panel `histRoot/histTitle/histBody`.
- **Helper functions (the contracts you'd rebuild):** `fmtMs/fmtDur/fmtBytes/fmtTok`,
  `estimateTokens`, `byteLen`, `tryParse`, `looksLikeBase64Blob`,
  `extractStringChars` (base64-skipping string-leaf sum), `outputCharsFromEvent`
  (text-only output sizing), `isPingEvent`, `usageFromEvent`, `parseServerTiming`,
  `captureRateLimit`, `callerStack`, `isMonitoredHost/isMonitoredApi/pathOf/convOf`,
  `analyzeBody` (async), `recordTurn`, `quantile/calcStats`,
  `histogramData` (shared compute) + `printHistogram` (console renderer),
  `ratesSnapshot/printRates`, `byConversation`, `runAssessment` (outliers +
  efficiency), schema probe: `runSchemaProbe/collectProbe/reportProbe`, HUD:
  `css/mkBtn/ensureHud/setCollapsed/updateHud/toggleHud/destroyHud/whenBody`,
  histogram panel: `ensureHistHud/destroyHistHud/renderHistHud`.
- **Turn record:** `{ id, conv, url, endpoint, isCompletion, ts, t0, t1, t2, ttft,
  ttftEvent, streamDuration, total, reads, events, reqBytes, inChars, attachments,
  estInputTokens, estOutputTokens, inputTokens, outputTokens, tokensReal,
  cacheRead, cacheCreate, streamBytes, tokPerSec, tokPerSecWall, interEventP50,
  interEventP95, status }`. `inputTokens`/`outputTokens` are the **effective**
  values (real usage when present, else the est); `est*` are always the heuristic;
  `inChars` is the raw content-char count used for self-calibration; `attachments`
  counts excluded base64 blobs; `isCompletion` flags chat-completion streams.
- **Flow:** `fetch` wrapper → `isMonitoredApi` gate → start `analyzeBody` (clone
  body), dispatch real fetch, `maxInFlight` update, `[REQ]` log, heartbeat →
  await response → `statusCounts`, `[RES]` + all headers + parsed Server-Timing +
  rate-limit → if `text/event-stream`, clone, decode + parse under the watchdog,
  capturing usage/cache + jitter → `recordTurn()` (emits `[SLOW]` when a turn
  beats the session p90, which is recomputed every `SLOW_P90_REFRESH` turns
  rather than re-sorted on every turn).
- **PerformanceObserver** logs `[TIMING]`: dns/tls/ttfb/resp **plus**
  `nextHopProtocol`, `transferSize`, `encodedBodySize`, `decodedBodySize`
  (observed with `buffered: true`). **WebSocket** wrapper logs `[WS]` open/close
  and counts frames for monitored hosts. Tab `visibilitychange` and
  `online`/`offline` are logged.

### Log tags
`[REQ]` (size + ~input tokens) · `[RES]` (status + all headers + parsed
Server-Timing + rate-limit) · `[FAIL]` · `[HANG]` (a non-aborting heartbeat; fires only past the per-endpoint warn bar, see Tunables) · `[SSE]` (events + ~output
tokens) · `[SSE STALL]` · `[SLOW]` (turn > session p90) · `[PERF]` (turn summary,
incl. real-vs-est source, cache tokens, steady/wall tok/s, inter-event gap) ·
`[TIMING]` · `[WS]` · `[TAB]`/`[NET]`.

---

## 4. Usage & token estimation (the honest part)

claude.ai does not publish a client-readable token count, and the model tokenizer
isn't public. The monitor therefore has **two sources**, in priority order:

1. **Real `usage` from the stream (exact, keyless)** — if claude.ai's SSE uses the
   public usage schema, the turn shows `tokensReal: true` and `inputTokens` /
   `outputTokens` are the model's own counts (see §2.8). Check the `src` column in
   `turns()` (`API` vs `~`).
2. **Heuristic (self-calibrating chars/token)** — used when no usage object is
   present. Starts at `EST_CHARS_PER_TOKEN` (3.6) and **self-calibrates**: every
   real-usage turn feeds `inChars` / `input_tokens` into a running `chars/token`
   ratio (see `_claudeDebug.calibration()`) that all later heuristic turns use.
   Input is the request body's string content (base64 attachments excluded),
   output the decoded text deltas. **The `~` marker means heuristic and nothing
   else** — it never appears on an exact (API) number anywhere in the UI.

What the figures are good for and not:

- **Good for:** usage *rates* and trends — messages/hour, messages/day, approx
  tokens/day, bytes up/down, tokens/sec throughput, and which conversation spends
  the most. Direction and relative magnitude are reliable even when a heuristic
  turn is off by ±15%.
- **Not good for:** exact billing on the heuristic path, and it does **not** show
  remaining plan headroom — subscription limits are usage-window based, not a
  published token budget. The captured rate-limit headers are the nearest proxy.
- A **model-free** signal is always available: `reqBytes` / `streamBytes` and the
  PerformanceObserver transfer sizes are exact and never touch content.

### 4.1 On-page overlays (no DevTools needed)
A small panel auto-appears top-right as a collapsed pill (`⏱ N turns · ~T tok`);
click to expand a live readout of turns, **session & chat time** (with gen/idle),
median/p90 total, median TTFT, estimated tokens, and last-1h / last-24h / per-day
rates, refreshing every `HUD_REFRESH_MS`.
Header buttons: **📊 histogram**, **🔬 schema probe**, **💡 assess**,
**⧉ copy JSON**, **▾ collapse**, **× hide**.
Toggle from code with `_claudeDebug.hud()` / `hud(true)` / `hud(false)`.

The **📊 button** opens a *second* panel that renders the histogram as DOM bars
(sized with `el.style.width`, CSP-clean) just below the main HUD. It updates only
on click (no per-second redraw) and **cycles the metric** on repeated clicks
through `HUD_HIST_METRICS` (total → ttft → ttftEvent → streamDuration →
outputTokens → inputTokens → tokPerSec → interEventP95 → reqBytes → streamBytes →
wrap). The panel has its own ×; closing the main HUD or `stop()` tears it down too.
Both overlays are built with `document.createElement` + `el.style.*` only.

### 4.2 Token caching in a long conversation (and its effect on the HUD)
**What caching is.** Anthropic supports *prompt caching*: a contiguous prefix of
the request — the system prompt, tool definitions, and the earlier, unchanged
turns — is stored server-side after its first use so it isn't re-processed on the
next turn. In a long chat the early history is byte-identical turn after turn, so
it's served from cache on later turns; only the new tail (your latest message +
the growing assistant reply) is fresh, uncached input.

**How the cache is keyed and invalidated.** The cache matches on an **exact,
contiguous prefix from the start of the request**. Appending to a conversation
preserves that prefix, so each new turn reuses it. But anything that changes
earlier content — editing or regenerating an earlier message, changing the system
prompt or tools, even a whitespace difference — **invalidates the cache from the
point of the change onward**; everything after it must be re-created. Cache
entries are also **ephemeral**: they expire after a short idle TTL (on the API,
~5 min by default, with a longer 1-hour option), so a thread you return to later
pays to re-create the prefix. (TTLs/pricing are API details that can change —
verify; the durable part is the accounting below.)

**The write-then-read pattern.** The first turn that establishes a given prefix
pays a one-time **cache-creation** cost (slightly more than normal input on the
API); later turns that reuse it pay a much cheaper **cache-read**. So across a
conversation the same history tokens are "created" once and "read" many times.

**How `usage` reports it.** Three separate fields:
- `input_tokens` — input that was **neither** read from nor written to cache (the
  fresh, uncached tail).
- `cache_read_input_tokens` — prefix served from cache this turn.
- `cache_creation_input_tokens` — prefix written to cache this turn.

The model's **total** context size for the turn is the **sum of all three**. (On
the API these bill at different rates — read cheap, create at a premium — but on a
claude.ai subscription you aren't billed per token; what matters here is the count.)

**What caching does to the per-turn input curve.** Without caching, *uncached*
input grows roughly **linearly** as the thread lengthens (the whole history is
reprocessed every turn). With caching, uncached `input_tokens` stays roughly
**flat and low** (just the new tail) while `cache_read_input_tokens` carries the
bulk and grows instead. Total context still grows, but the fresh/expensive portion
does not.

**Effect on the HUD's two paths.**
- **Real-usage path (`src: API`).** The monitor captures all three fields. The
  "in tok" column (`inputTokens`) is the **uncached** count; `cacheRead` /
  `cacheCreate` show separately (per-turn `[PERF]` "cache tokens" line; "cache rd"
  column in `rates()`). In a long cached thread `inputTokens` stays small while
  `cacheRead` climbs — that divergence *is* caching. **To reconstruct full prompt
  size, add the three** — `rates()` shows a "total ctx" column that does this. The
  summary's `tokensTotal` and the "in tok" roll-up use the **uncached**
  `inputTokens`, so they reflect *fresh* consumption, not total context.
- **Heuristic path (`src: ~`).** The monitor measures the *entire resent body
  every turn* and has **no concept of caching**, so its input estimate climbs
  roughly linearly with conversation length and **overstates** the fresh input
  that caching makes cheap. Read it as "total context resent this turn," not "new
  tokens."
- **Net:** `src: API` → trust the uncached-vs-cache split and sum for totals;
  `src: ~` → the number is caching-blind and tracks total-context-resent, inflating
  on long threads.

**Caveat:** the real-usage path (and therefore every cache figure) only works if
claude.ai's internal stream actually emits the public `usage` schema with these
cache fields. If it doesn't, the cache columns stay null/zero and only the
caching-blind heuristic is available — the `src` column tells you which world
you're in.

### 4.3 Where your input tokens come from
Two different lenses — the **model's** input vs **what the monitor can see**.

**The model's input tokens per turn** = everything in the context window for that
turn: the system prompt, any tool definitions, the **entire retained conversation
history** (all prior user + assistant turns, including extended-thinking tokens),
your current message, and the **extracted text of every attached file**. Files
"sit in the context window" after upload and are re-counted as part of history on
each later turn until they fall out of the rolling window.

- **Typed / pasted text** → counts (part of your message and then history).
- **Uploaded documents** (PDF, DOCX, TXT, RTF, ODT, HTML, EPUB, JSON, CSV, MD) →
  their extracted text is inlined into context and counts. PDFs: visual analysis
  covers roughly the first ~100 pages; text beyond is still read.
- **Images** (JPEG/PNG/GIF/WebP) → counted by a **tile** formula (~`(w·h)/750`),
  not by file/base64 size.
- **`.zip` archives** → depends on *where* you upload:
  - **Chat composer (drag/drop into a chat):** the composer does **not** expand a
    zip, so its contents aren't read in that chat — unzip and add the files
    yourself, or use a third-party extractor.
  - **Projects knowledge base / a project working directory:** the zip **is
    expanded** into its individual files in the right place, and those files become
    available to the project. This is the common "upload a zip, it gets unzipped"
    experience.
  - **Agentic / Files-API contexts:** a sandbox extracts archives via `bash`.
  (Product behavior; verify in-app, it can change.)

**What the monitor can see** is only the intercepted completion request body:
- It counts the **resent history + current message + any attachment text inlined
  into that body**. So pasted text and inlined file text *are* reflected.
- Content uploaded via a **separate endpoint and referenced by id** (so it's
  attached server-side, not in the completion body) is **invisible** to the
  heuristic → undercount. Inlined **base64 images** are deliberately excluded from
  the char estimate (tiles, not chars) → also an undercount of image cost.
- The **real-usage path sidesteps all of this**: `input_tokens` (+ cache fields)
  reflect everything the model actually saw, regardless of how it reached the
  request. That's the accurate number when the stream exposes it.

**To be unambiguous:** files you drag/drop into a chat **do** count toward your
token usage — the model reads their extracted text and it consumes context, the
same as typed text. The subtlety above is only about what the *monitor* can
**measure** on its heuristic path, not about whether the tokens count.

**Projects count differently.** Knowledge-base files don't all enter context every
turn: while project knowledge is small it's loaded wholesale, but once it
approaches the window claude.ai switches to **RAG** and retrieves only the relevant
chunks per question. So a big expanded zip in a project costs tokens only for the
chunks actually pulled into a given turn — unlike a chat attachment, which sits
fully in context until it scrolls out of the rolling window.

### 4.4 Schema probe (the 🔬 button / `_claudeDebug.probe()`)
Real-usage capture, output sizing, conversation-id parsing, and completion
classification all depend on claude.ai's **undocumented** internal shapes, so the
probe lets you confirm they still match. Arm it (🔬 button or
`_claudeDebug.probe()`), send one message, and the next streamed turn is analyzed
— **keys only, never content** — and a PASS/WARN/FAIL report prints:

- request body parsed? top-level keys; content-char count; attachments excluded.
- endpoint classified as a completion (so it counts as a message)?
- conversation id parsed from the URL?
- `usage` object present, and does it carry `input_tokens` / `output_tokens`
  (+ cache fields)? If absent → tokens are heuristic.
- content deltas recognized (`delta.text` / `partial_json`)? If a `delta` is
  present but unrecognized → **FAIL**: output estimate is unreliable, update
  `outputCharsFromEvent()`. The report lists the actual delta keys and event types.

It analyzes one turn then disarms. The fastest way to detect — and fix — a
claude.ai shape change that would otherwise silently degrade the token figures.

### 4.5 Session time vs chat time (and engaged / idle)
The HUD tracks three distinct clocks, all in JS, all separate from any
assistant-side timer:

- **Session time** — wall-clock since the monitor **loaded** on this page
  (`SESSION_START`, set at injection). Includes *everything*: idle, reading,
  typing, and the stretch before your first message. Resets on refresh (the
  monitor is in-memory).
- **Chat time** — wall-clock from your **first** recorded turn to your **most
  recent** (`lastTurnTs − firstTurnTs`). The active-conversation span; it's zero
  until you've sent a message, and unlike session time it ignores the idle period
  before you started.
- **Engaged (generating) time** — the **sum of per-turn durations** (`engagedMs`):
  how long Claude was actually producing. Its complement, **idle** = chat −
  engaged, is the time you spent reading/typing between turns. (Engaged can exceed
  chat if requests overlap — concurrent in-flight turns.)

So: session ≥ chat ≥ engaged in a normal single-stream session. They are three
different things, all derivable from data already captured (`SESSION_START`, the
per-turn `ts`, and `total`). See `_claudeDebug.time()` and the HUD "time" line.
(Want per-conversation spans too? `byConversation()` groups turns by conversation
id; a min/max `ts` per group would give each conversation its own chat span — a
small addition if useful.)

### 4.6 Assessment — outliers & efficiency (the 💡 button / `_claudeDebug.assess()`)
A session-relative analysis. With ≥3 turns it computes baselines (median/p90
total, median TTFT) and flags, each with a recommendation where actionable:

- **Slow-turn outliers** — turns beyond p90 *and* > `ASSESS.slowVsMedian`× median (default 1.5), labelled
  TTFT-dominated (server/network) vs streaming-dominated (long output).
- **TTFT spikiness** — p90 > `ASSESS.ttftSpike`× median (default 2; intermittent server slowness).
- **input:output ratio** — a high ratio means lots of context per unit of answer.
- **Context bloat** — input grown past `ASSESS.ctxGrowth`× (default 4) since the
  oldest retained turn → suggests a fresh chat or a summary (a long thread
  re-sends everything each turn).
- **Cache utilization** (real-usage turns) — hit ratio below `ASSESS.cacheHitLow`
  (default 0.3) on a long thread → caching isn't carrying your context (often from
  editing earlier messages).
- **Throughput dips** — turns generating < `ASSESS.tpsDip`× the median tok/s (default 0.5).
- **Errors** — fetch failures and 4xx/5xx counts.
- **Engaged vs idle** time for the session.

Caveat baked into the output: "typical" means relative to **this** session, not a
global baseline, and the signals are correlations — the monitor sees the captured
metrics, not your intent.

---

## 5. Console API

Call with parentheses:

| Call | Does |
|---|---|
| `_claudeDebug.report()` | summary + usage rates + histogram + health |
| `_claudeDebug.hud(show?)` | toggle the on-page overlay (auto-shown collapsed) |
| `_claudeDebug.histogramHud(metric?)` | open the DOM histogram panel for a metric |
| `_claudeDebug.rates()` | rolling streams/completions/tokens (in/out/total-ctx/cache)/bytes over 1m/5m/1h/24h + daily projection, with an exact/total column |
| `_claudeDebug.byConversation()` | per-conversation message/token totals |
| `_claudeDebug.health()` | peak in-flight, current in-flight, fetch failures, HTTP status mix, last rate-limit |
| `_claudeDebug.rateLimits()` | most recent rate-limit headers seen |
| `_claudeDebug.probe()` | arm a schema probe; the next streamed turn is analyzed for parser/shape problems |
| `_claudeDebug.assess()` | outliers + efficiency assessment with recommendations (session-relative) |
| `_claudeDebug.time()` | session / chat / engaged / idle time |
| `_claudeDebug.calibration()` | the current self-calibrated chars/token and sample size |
| `_claudeDebug.stats()` | min/median/p90/max for both TTFTs, stream, total |
| `_claudeDebug.histogram(metric?, buckets?)` | ASCII histogram; metric ∈ `total`, `ttft`, `ttftEvent`, `streamDuration`, `outputTokens`, `inputTokens`, `tokPerSec`, `tokPerSecWall`, `interEventP95`, `cacheRead`, `reqBytes`, `streamBytes` |
| `_claudeDebug.turns()` | per-turn table (timings, events, endpoint, in/out tokens, cacheRd, `src` API/~, tok/s, gapP95) |
| `_claudeDebug.pending()` / `.count()` | in-flight requests |
| `_claudeDebug.sockets()` | WebSocket activity (recv/sent/state) |
| `_claudeDebug.export()` | copy all turn data as JSON to clipboard |
| `_claudeDebug.reset()` | clear the turn log **and chat clocks** (keeps calibration, health, and the session clock) |
| `_claudeDebug.resetAll()` | clear everything except the session clock (turns, sockets, chat clocks, calibration, health) |
| `_claudeDebug.callers(on=true)` | toggle per-request caller-stack capture in `[REQ]` logs (off by default — a perf trade) |
| `_claudeDebug.stop()` | restore fetch **and** WebSocket, detach everything (incl. overlays) |

Use **without** parentheses (Live-Expression-safe getters):

| Getter | Returns |
|---|---|
| `_claudeDebug.data` | snapshot array of all turns |
| `_claudeDebug.summary` | `{turns, inFlight, lastTotalMs, medianTotalMs, p90TotalMs, medianTTFTMs, tokensTotal, exactTurns, sessionMs, chatMs, engagedMs, msgsLastHour, msgsLast24h}` (`tokensTotal` = effective in+out; `exactTurns` = real-usage count; `sessionMs`/`chatMs`/`engagedMs` = the three clocks in §4.5) |

No `.help()` — the script prints its own cheat sheet on load.

---

## 6. Install & update

1. `chmod +x claude_browser_extension.sh && ./claude_browser_extension.sh`
   → builds `claude-debug-extension/` (manifest.json + the JS).
2. `chrome://extensions` → **Developer mode** → **Load unpacked** → pick the folder.
3. Open/refresh claude.ai, open DevTools → Console (purple banner confirms active).
4. After editing the JS: click ↺ on the card, then refresh the page.

Firefox: `"world": "MAIN"` needs 128+; load via `about:debugging` → Load
Temporary Add-on → pick `manifest.json`.

The `.sh` writes `manifest.json` and `claude_developer_debug.js` via two quoted
heredocs (`<< 'EOF'`, so no shell expansion inside the JS). `set -euo pipefail`
guards the build. To recreate the project you only need those two files plus the
manifest in §2.1.

---

## 7. How it was validated

Static + sandbox checks (no browser needed):
- `bash -n` on the builder; `node --check` on the extracted JS; manifest JSON parse.
- **Load smoke test:** stub a minimal `window/document/performance/PerformanceObserver`,
  `eval` the IIFE, confirm all `_claudeDebug` methods exist and every empty-state
  path runs without throwing.
- **End-to-end turn:** drive `window.fetch` with a synthetic `text/event-stream`
  `Response` (real `ReadableStream`) carrying `message_start`/`content_block_delta`/
  `message_delta` usage + a base64 attachment in the request — assert real usage is
  preferred, cache tokens captured, base64 + framing excluded from estimates,
  `ping`/`[DONE]` not counted, conversation id + endpoint parsed, and the original
  response returned untouched.
- **DOM test of the histogram panel:** feed several turns, render the panel, assert
  bar rows are built, the metric cycles on click, and × removes the panel.

The generator embeds a byte-identical copy of the JS; rebuild + `diff` to verify.

---

## 8. Limitations & caveats

- **fetch + WebSocket only.** `XMLHttpRequest` and `EventSource` are not
  intercepted.
- **Heuristic tokens are estimates** (self-calibrated chars/token, default 3.6)
  and **caching-blind** (§4.2);
  they measure *consumption*, not remaining plan *headroom*. The **real-usage**
  path is exact but only fires if claude.ai's stream uses the public `usage`
  schema (watch the `src` column).
- **Images** are excluded from the char estimate (tile-based, not char-based), so
  the heuristic undercounts image-heavy turns; **files referenced by id** (not
  inlined in the completion body) are invisible to the heuristic too.
- **claude.ai's internal request/SSE shapes are undocumented** and can change
  without notice — that would disable usage capture (fall back to heuristic) and
  degrade conversation parsing. Latency, byte, header, and timing metrics are
  schema-independent and keep working.
- **clone() backpressure:** a long stream buffers its unread remainder if the page
  and monitor read at different speeds; the idle watchdog bounds the worst case.
- **Privacy:** prompt/response content is parsed locally for sizing only and is
  never logged; nothing leaves the browser (the monitor uses no API key at all).
- **In-memory only**, resets on refresh, capped at `MAX_TURNS` / `MAX_SOCKETS`.
- Caller stacks are best-effort and engine-dependent.

---

## 9. Gotchas cheat-sheet

- See nothing? Almost certainly the **isolated world** — check `"world": "MAIN"`
  and Chrome ≥ 111.
- Console scrolling forever? A **printing helper in a Live Expression** — move it
  to the `>` prompt; use `.data`/`.summary` (no parens) for live views.
- `turns()` `src` column: **`API`** = exact from the stream's usage object;
  **`~`** = heuristic (self-calibrated chars/token; see `calibration()`). The `~`
  marker means heuristic and never appears on an exact number.
- Input estimate huge on a long thread? Heuristic counts the whole resent body and
  is **caching-blind** — prefer the real-usage split (uncached + cacheRead) when
  `src` is `API`.
- A `~` on a number means it's a **heuristic estimate**, not exact.
- Histogram says "not enough data" — needs **2+ completed turns**.
- 📊 panel sits below the main HUD and only redraws on click; click again to cycle
  metric. It positions relative to the HUD at click time (won't follow live).
- Token estimates drifting oddly, or `src` flipped to `~`? claude.ai may have
  changed its internal body/SSE shape — the byte/latency/header metrics still hold.
- Don't add `eval`/`new Function`/string timers, inline HTML, or `<style>` — **CSP**
  will throw; build DOM with `createElement` + `el.style.*`.
- Token figures look wrong or `out` reads 0? Run the **🔬 schema probe**
  (`_claudeDebug.probe()`) — it pinpoints which assumption (usage shape, delta
  field, endpoint, conversation id) stopped matching claude.ai.
- Want a read on outliers/efficiency? **💡 `_claudeDebug.assess()`** flags slow
  turns, context bloat, low cache reuse, throughput dips, and errors with
  recommendations (session-relative).
- Always return the **original** response to the page; only ever read a `clone()`.
