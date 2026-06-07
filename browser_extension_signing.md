# browser_extension_signing.md

A decision-tree guide for getting **`claude_browser_extension.sh`** and
**`claude_browser_extension_2.sh`** signed by Mozilla and installed permanently
in Firefox. Covers every reasonable distribution path with copy-pasteable
commands.

> The two `.sh` scripts each emit a Manifest V3 extension folder plus a
> `web-ext`-built `.zip`/`.xpi`. Everything below picks up from there — you've
> already run the script and have the unpacked folder + `.zip`/`.xpi` ready.

---

## TL;DR — pick a path

| If you want… | Path | Time | Reach |
|---|---|---|---|
| One-session test on any Firefox | **Temporary** (no signing) | 30 seconds | This browser, until close |
| Permanent on **your own Nightly / Dev Edition / ESR** | **B — Unsigned + pref off** | 2 minutes | This browser |
| Permanent on **your own stock Release / Beta** Firefox | **A — Unlisted, self-distributed** | ~5 minutes (after one-time setup) | This browser; you can also share the `.xpi` |
| Ship to **other people** without an AMO listing | **A** + host the `.xpi` yourself | ~5 minutes per build | Anyone you give the URL to |
| Ship to **other people** via the public AMO catalog | **C — Listed (web UI)** or **D — Listed (CLI)** | Hours to weeks (manual review possible) | Anyone on AMO |

The realistic default for solo dev work on Release Firefox is **Path A**.
The realistic default for Nightly users is **Path B**.

---

## 1. Why Firefox forces this choice

Firefox refuses to permanently install an unsigned `.xpi` on stock Release/Beta
by design. Only Mozilla can sign for Release/Beta, and they only sign through
AMO (addons.mozilla.org). The two AMO outcomes:

- **Listed** — submitted to the public catalog. Anyone can find and install it.
- **Unlisted** (a.k.a. *self-distributed*) — same signing infrastructure, but
  the result is a signed `.xpi` you host yourself. Not searchable on AMO. This
  is what `web-ext sign --channel=unlisted` does.

Nightly / Developer Edition / ESR ignore this entirely if you flip a pref.
Stock Release / Beta do not.

---

## 2. Common prerequisites (all paths except Temporary)

### 2.1 — A working build

Both scripts already produce these via `web-ext build`:

```
claude-debug-extension/                ← script 1 unpacked folder
claude-hud2-extension/                 ← script 2 unpacked folder
web-ext-artifacts/
    claude_developer_debug-<ver>.xpi   ← script 1 packaged
    claude_hud_2_actions-<ver>.xpi     ← script 2 packaged
```

If you don't have these, run the relevant `.sh` first.

### 2.2 — Mozilla AMO account (needed for any AMO path: A, C, D)

1. Create an account at <https://addons.mozilla.org/developers/>.
2. Accept the **Firefox Add-on Distribution Agreement**.
3. Create API credentials at
   <https://addons.mozilla.org/developers/addon/api/key/>.
   You get a **JWT issuer** (looks like `user:1234567:567`) and a **JWT
   secret** (a long random string). Store these somewhere safe — they're what
   `web-ext sign` uses to authenticate.

### 2.3 — Stable extension ID in the manifest

AMO refuses to sign an extension without a stable, explicit ID in
`browser_specific_settings.gecko.id`. Both scripts ship with one:

| Script | Manifest gecko.id |
|---|---|
| `claude_browser_extension.sh`   | `claude-developer-debug@local` |
| `claude_browser_extension_2.sh` | `claude-hud2@local` |

These are fine as long as you never need to ship under that ID from a different
developer account. If you want a more conventional form (`name@yourdomain`),
edit the manifest heredoc in each script. **The ID is what AMO uses to match
new uploads to existing add-on records, so don't change it after the first
successful signing or you'll be making a brand-new add-on.**

### 2.4 — Data collection declaration (AMO requirement since 2025-11-03)

As of November 3 2025, AMO requires every **new** extension submission to
declare its data collection practices in
`browser_specific_settings.gecko.data_collection_permissions`. Both scripts
ship with `{ "required": ["none"] }`, which truthfully declares that neither
extension collects or transmits any personal data.

If you ever change either extension to actually collect data (don't), update
this value to the appropriate combination from Mozilla's vocabulary:
`authenticationInfo`, `bookmarksInfo`, `browsingActivity`,
`financialAndPaymentInfo`, `healthInfo`, `locationInfo`,
`personalCommunications`, `personallyIdentifyingInfo`, `searchTerms`,
`websiteActivity`, `websiteContent`. See
<https://extensionworkshop.com/documentation/develop/firefox-builtin-data-consent/>.

Firefox shows this disclosure to the user at install time, alongside the
permission prompts. `"none"` produces a "no data collected" badge in the
install UI.

### 2.5 — Version bumping

AMO refuses any new upload at a version it has already signed. Bump the
`"version"` field in the manifest heredoc inside the `.sh` before re-running
the script and re-signing. Use the standard four-component dot form
(`1.7` → `1.7.1` → `1.8`). Don't reuse a version.

---

## 3. Path: Temporary (no signing, any Firefox 109+)

For one-session smoke tests. Wiped when Firefox closes; also wiped on crash.

1. `about:debugging` → "This Firefox"
2. "Load Temporary Add-on…"
3. Pick `claude-debug-extension/manifest.json` (or `claude-hud2-extension/manifest.json`)
4. Refresh `claude.ai`

That's it. Lifetime: until the next Firefox close.

---

## 4. Path B: Unsigned + pref off (Nightly / Developer Edition / ESR ONLY)

Skips Mozilla entirely. Will **not** work on stock Release / Beta Firefox.

### Commands

1. Open `about:config`.
2. Find `xpinstall.signatures.required`, set it to **false**.
3. Open `about:addons`.
4. Click the gear ⚙ icon → **Install Add-on From File…**
5. Pick the `.xpi` the script built (e.g.
   `web-ext-artifacts/claude_developer_debug-1.7.xpi`).

Lifetime: until you remove it. Updates: manual (re-run the `.sh`, bump the
version, install the new `.xpi`). Stock Release / Beta Firefox ignore the
pref and will refuse the install — **only the developer-oriented channels
honor it.**

---

## 5. Path A: Unlisted, self-distributed (RECOMMENDED for solo Release-Firefox use)

This is the right answer for "I want my extension to install permanently on
my own stock Firefox without publishing it." Mozilla signs the `.xpi`; you
host and install it yourself; it never appears on AMO.

### 5.1 — One-time setup

```bash
# from outside the extension folder:
export AMO_JWT_ISSUER='user:1234567:567'           # from §2.2
export AMO_JWT_SECRET='your-long-jwt-secret-here'
```

(Put these in a file you `source`, not in your `~/.bashrc` — they're
credentials.)

### 5.2 — Sign

```bash
cd claude-debug-extension                          # or claude-hud2-extension
web-ext sign --channel=unlisted \
    --api-key="$AMO_JWT_ISSUER" \
    --api-secret="$AMO_JWT_SECRET"
```

`web-ext` uploads the build to the AMO Submission API v5, polls for validation,
and downloads the signed file. Automated review for unlisted extensions
**normally returns a signed `.xpi` in seconds**, but Mozilla can flag any
submission for manual review at any time. Output ends up at:

```
claude-debug-extension/web-ext-artifacts/<extension>-<ver>-an+fx.xpi
```

The `an+fx` suffix indicates it's an Android+Firefox-signed build.

### 5.3 — Install

`about:addons` → gear ⚙ → **Install Add-on From File…** → pick the signed
`.xpi`. Stays installed until you remove it. Works on **any** Firefox channel.

### 5.4 — Auto-updates (optional)

By default, signed unlisted add-ons don't auto-update — users (you) reinstall
the new `.xpi` manually. To enable auto-updates:

1. Add a `update_url` to the manifest's `browser_specific_settings.gecko`:
   ```json
   "browser_specific_settings": {
     "gecko": {
       "id": "claude-developer-debug@local",
       "update_url": "https://your-host.example/claude-debug-updates.json"
     }
   }
   ```
2. Host a JSON file at that URL in Firefox's update-manifest format:
   ```json
   {
     "addons": {
       "claude-developer-debug@local": {
         "updates": [
           {
             "version": "1.8",
             "update_link": "https://your-host.example/claude_developer_debug-1.8.xpi"
           }
         ]
       }
     }
   }
   ```
3. Every time you release a new version, sign it (§5.2), upload the new
   `.xpi` to your host, and update the JSON.

Firefox checks `update_url` periodically. For a single-user installation this
is overkill — just reinstall by hand.

---

## 6. Path C: Listed via the AMO web UI

For shipping to other people via the public AMO catalog.

### 6.1 — First submission

1. Sign in at <https://addons.mozilla.org/developers/>.
2. Click **Submit a New Add-on**.
3. Choose **"On this site"** (= listed). The alternative **"On your own"**
   would put you on Path D.
4. Upload the `.xpi` from `web-ext-artifacts/`.
5. AMO runs automated validation. If it passes, you continue to the metadata
   form.
6. Fill in:
   - **Name** — shown to users; can differ from the manifest name.
   - **Summary** — one paragraph, plain text.
   - **Description** — long form, supports basic HTML.
   - **Categories** — pick what fits (Productivity, Developer Tools…).
   - **Tags**, **Support email**, **Support site**.
   - **License** — pick one (MIT, Apache-2, BSD, MPL-2.0, etc.).
   - **Privacy policy** — **required** for both these extensions (they do
     network-relevant things; AMO will block submission without one). See §9
     for ready-to-paste text per script.
   - **Screenshots** — at least one.
7. Submit for review.

### 6.2 — What review looks like

- Automated review may sign and publish in minutes to ~24 hours for trivial
  extensions.
- Manual review is common on first submission for anything that does
  `fetch` interception (script 1) or pulls remote content
  (script 2). Manual review can take days to a few weeks.
- The reviewer reads your code. They'll send questions if anything looks
  unclear. Use the **Notes for Reviewers** field on submission to head off
  the obvious questions (§10).

### 6.3 — Updates after listing

For subsequent versions, you can either:

- Submit through the web UI again (Add-on Versions → Upload New Version), or
- Use the CLI: `web-ext sign --channel=listed --api-key=... --api-secret=...`
  (you only need to fill metadata on the first version; later versions
  inherit it).

Listed add-ons auto-update via AMO's update server — users get the new
version automatically once it's signed and published. **You don't need
`update_url` for listed add-ons.**

---

## 7. Path D: Listed via `web-ext sign --channel=listed`

Same outcome as Path C but driven from the CLI. Use this when scripting CI.

```bash
cd claude-debug-extension
web-ext sign --channel=listed \
    --api-key="$AMO_JWT_ISSUER" \
    --api-secret="$AMO_JWT_SECRET"
```

Caveats:

- **First version**: the CLI uploads but doesn't let you fill metadata
  (name shown on AMO, description, screenshots, privacy policy). You'll need
  to go to the AMO developer hub to complete the listing before it's
  publicly visible.
- **Subsequent versions**: the CLI uploads + the existing listing metadata
  carries over. CI-friendly.

If you're publishing the first listed version, **use Path C** (web UI) for
the initial submission and switch to Path D for follow-ups.

---

## 8. Branch picker — full decision tree

```
Do you need it installed PERMANENTLY?
├── No  → Temporary (§3). Done.
└── Yes
    │
    Are you on Nightly / Developer Edition / ESR?
    ├── Yes, and you don't want to deal with Mozilla
    │       → Path B (§4). Done.
    │
    └── No — stock Release / Beta — OR — you want signing anyway
        │
        Who installs this?
        ├── Only you (or a handful of people you give the .xpi to)
        │       → Path A: unlisted self-distributed (§5).
        │
        └── Anyone on the internet who searches AMO
            │
            Is this the first ever version?
            ├── Yes  → Path C: web UI (§6).
            └── No   → Path D: web-ext sign --channel=listed (§7).
```

---

## 9. Privacy policy text (ready-to-paste, per script)

AMO requires a privacy policy for any extension that does anything
network-related. Both these extensions do.

### 9.1 — `claude_browser_extension.sh` (the debug monitor)

```
Privacy Policy — Claude Developer Debug

WHAT IT DOES
This extension instruments the claude.ai web page in the user's own browser
to measure request/response timing, server-sent-event streaming behaviour,
and turn latency. Its purpose is to give developers visibility into their
own conversations with Claude.

DATA COLLECTION
This extension does not collect any data. Nothing is sent to any server
operated by the extension author or any third party. All measurements are
computed locally in the browser and exist only as JavaScript values in the
page's own memory. They are discarded when the page is closed or reloaded.

NETWORK ACCESS
The extension does not make any network requests of its own. It observes
requests that claude.ai itself makes (by wrapping the page's fetch and
XMLHttpRequest objects) to extract timing information. The observed
request and response bodies are passed back to claude.ai unmodified.

SCOPE
The extension only runs on https://claude.ai/* (declared in the manifest
"matches" field). It does not run on any other site.

DATA RETENTION
None. There is no persistence layer. Refreshing the page clears all state.

CONTACT
[your email or repo URL]
```

### 9.2 — `claude_browser_extension_2.sh` (the HUD)

```
Privacy Policy — Claude HUD 2

WHAT IT DOES
This extension adds a small floating panel to claude.ai with three actions:
populate the "Instructions for Claude" settings field from a preferences
file the user has chosen, read the current plan name from the billing page,
and list command shortcuts parsed from the preferences file.

DATA COLLECTION
This extension does not collect any data. Nothing is sent to any server
operated by the extension author or any third party. The plan name, when
read, is displayed in the HUD inside the browser and is not transmitted
anywhere.

NETWORK ACCESS
The extension makes one kind of outbound request: it fetches the user's
preferences file from a public URL on raw.githubusercontent.com (the
PREFS_URL constant in the source code). The URL points to a public file
controlled by the user; no credentials are sent and no data from the
browser is transmitted with the request. The fetched text is used only to
populate the claude.ai settings textarea and to parse the command list.

The host raw.githubusercontent.com is declared in the manifest
"host_permissions" field; this is required to bypass claude.ai's
Content-Security-Policy connect-src rule, which would otherwise block the
fetch.

SCOPE
The extension only runs on https://claude.ai/* (declared in the manifest
"matches" field). It does not run on any other site.

DATA RETENTION
None. There is no persistence layer. Refreshing the page reloads the
preferences and discards all in-memory state.

CONTACT
[your email or repo URL]
```

Tighten or expand to match what you actually do; the structure above is what
AMO reviewers look for.

---

## 10. Notes for reviewers (paste into the AMO submission form)

When manual review happens, getting ahead of the obvious questions cuts the
review time.

### 10.1 — `claude_browser_extension.sh`

```
This extension instruments fetch() and XMLHttpRequest on claude.ai to
measure request and turn latency. It is read-only — bodies are tee-d via
.clone() and the original Response is returned to the page unmodified.

WHY "world": "MAIN":
  The patch must run in the page's own JavaScript world so that
  window.fetch is the same object claude.ai's bundle uses. An ISOLATED-
  world content script gets its own window.fetch, which would not
  intercept the page's requests. world=MAIN is the documented mechanism
  for this case (Chrome 111+, Firefox 128+).

WHY "run_at": "document_start":
  To patch fetch before claude.ai's bundle runs, so the very first
  request is observed.

NETWORK BEHAVIOUR:
  The extension makes no outbound requests of its own. It only observes
  requests claude.ai already makes.

NO DATA EXFILTRATION:
  Nothing is sent anywhere by this extension. All observation results are
  JavaScript values in the page's memory, accessible from the DevTools
  console as _claudeDebug.* for the user to inspect.

NO REMOTE CODE:
  The extension does not load or execute any remote scripts. The full
  source is the bundled claude_developer_debug.js.

PERMISSIONS:
  The only "matches" entry is https://claude.ai/*. There are no host
  permissions and no chrome.* APIs are used (MAIN-world content scripts
  cannot use chrome.* — this extension does not need any).
```

### 10.2 — `claude_browser_extension_2.sh`

```
This extension adds a small floating HUD to claude.ai with three buttons:
fill the settings "Instructions for Claude" field, read the current plan
name, and list command shortcuts.

NETWORK BEHAVIOUR:
  The extension makes one type of outbound request: a fetch() to a fixed
  public URL on raw.githubusercontent.com (the PREFS_URL constant in
  claude_hud2.js). No credentials are sent. No data from the browser is
  transmitted with the request — it is a plain GET of a public file. The
  response is treated as TEXT, displayed in the settings textarea, and
  parsed for command tokens. The response is never executed as code.

WHY host_permissions FOR raw.githubusercontent.com:
  The fetch happens from an ISOLATED-world content script. claude.ai's
  Content-Security-Policy connect-src rule would block any direct page-
  context fetch to that host. Declaring it in host_permissions causes
  Firefox/Chrome to issue the request from the extension context, which
  is exempt from the page CSP. The host is the narrowest one that works
  — no wildcards beyond what the platform requires.

WHY NOT "world": "MAIN":
  Because that would put us inside the page CSP and block the fetch.
  Running in the isolated world is intentional. The React value-setter
  needed to drive the settings textarea works fine across the world
  boundary because the DOM is shared.

NO DATA EXFILTRATION:
  Nothing is sent anywhere by this extension. The plan name read from the
  billing page is rendered into the HUD and discarded on reload.

NO REMOTE CODE EXECUTION:
  The fetched preferences are TEXT, used to populate a settings field and
  parse command labels. The text is never eval()'d, never inserted as
  HTML, and never executed.

PERMISSIONS:
  "matches" is limited to https://claude.ai/*. "host_permissions" is
  limited to https://raw.githubusercontent.com/*.
```

---

## 11. Troubleshooting

### "web-ext sign" hangs or times out
The signing API can be slow under load. Default `web-ext` timeout is
generous; if it really hangs, ^C and retry. The version is already uploaded
so you may need to bump the version number to retry from a clean slate.

### "Add-on with ID … already exists"
You've already signed this version. Bump `manifest.json`'s `"version"` and
re-run the script (which re-runs `web-ext build`), then re-sign.

### "Validation failed"
Run `web-ext lint --source-dir claude-debug-extension` to see what AMO's
validator is complaining about. The common ones are:
- Missing `browser_specific_settings.gecko.id`.
- A manifest field type mismatch (string where array expected, etc.).
- Use of an MV3 API the validator doesn't recognise on your `manifest_version`.

### Signed `.xpi` won't install — "this add-on could not be installed because it appears to be corrupt"
Almost always means the file got truncated during download or the signing
process didn't actually complete. Re-sign and verify the file size matches
what `web-ext` reported on stdout.

### Signed on AMO but Firefox still won't install
Check that the gecko ID in the manifest you signed matches what you have
locally. If you signed `claude-debug-extension@local` and renamed the local
copy to `claude-developer-debug@local`, the signature is invalid for the
new ID.

### Manual review takes weeks
This is normal for first listed submissions of extensions that intercept
network traffic. Make sure your reviewer notes (§10) are thorough — every
question the reviewer doesn't have to ask saves a round trip.

### `web-ext lint` warns "KEY_FIREFOX_UNSUPPORTED_BY_MIN_VERSION" for data_collection_permissions
The `data_collection_permissions` key needs Firefox 140+ (desktop) / 142+
(Android) to take effect. Both scripts ship with a lower `strict_min_version`
because they don't actually need the key to function — on older Firefox it's
silently ignored, which is correct behavior when the declared value is
`"none"` (there's nothing to disclose). **The warning is non-blocking** —
AMO accepts the submission. To silence it, bump `strict_min_version` to
`140.0` in the manifest (and add `"gecko_android": { "strict_min_version":
"142.0" }`) — but that also forbids install on Firefox versions between
the original minimum and 140, which is a real cost. Leave it warning-only
unless you're actually starting to collect data.

---

## 12. Quick-reference command summary

| Goal | Command |
|---|---|
| Build (any path) | `./claude_browser_extension.sh` |
| Lint before signing | `web-ext lint --source-dir claude-debug-extension` |
| Sign for self-distribution | `web-ext sign --channel=unlisted --api-key=... --api-secret=...` |
| Sign + submit listed | `web-ext sign --channel=listed --api-key=... --api-secret=...` |
| Validate without uploading | `web-ext lint --source-dir <dir>` |
| Run unsigned locally (Firefox) | `web-ext run --source-dir <dir>` (launches a fresh Firefox with the extension loaded) |

---

## 13. What this guide does NOT cover

- Chrome Web Store publishing (different submission, different signing, $5
  one-time developer fee, different policies). Both extensions install
  unpacked in Chrome via Developer Mode with no signing needed.
- Microsoft Edge Add-ons store (Chromium-based, similar to Chrome).
- Opera, Brave — they load the unpacked folder directly, same as Chrome.
- Mobile Firefox add-on signing (a separate AMO submission flow and a much
  shorter allow-list of supported extensions).
