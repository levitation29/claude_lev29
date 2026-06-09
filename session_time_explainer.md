# session_time_explainer.md

Two different clocks and how each determines "start." Used by `session_time` /
`session_time_header` (current-container) and `chat_time` (wall-clock), and by the
`showhotfs` /mnt/project fallback.

## Two clocks, two questions

| clock | question it answers | anchor | survives container restart? |
|---|---|---|---|
| current-container | how long has THIS live container been up (since I last got compute)? | container boot `btime` | no — resets on restart (by design) |
| wall-clock | how long since I first opened this chat? | earliest persistent chat artifact | yes |

A chat's container can reboot mid-conversation (see below); the working filesystem
is restored but `btime` jumps forward. The two clocks diverge exactly then —
observed in one chat: container booted 16:19 UTC while the chat had actually opened
~07:14 (9h earlier).

## The signals

- **`btime`** (current-container): `awk '/^btime/{print $2}' /proc/stat`,
  corroborated by `stat -c %Y /` and `/etc/hostname` mtime. Always present, no
  setup, resets per container.
- **chat-open anchor `co`** (wall-clock, persistent): the earliest mtime in
  `/mnt/user-data/uploads/`. Uploads are immutable and survive restarts, and the
  first one is the first thing you sent (≈ chat open). Falls back to
  `tmp_session_start` (only if `touch_start`/`xyzzy`/`resume` ran), then to `btime`:
  ```sh
  co=$(find /mnt/user-data/uploads -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1 | cut -d. -f1)
  s=$(stat -c %Y /home/claude/tmp_session_start 2>/dev/null || echo)
  if [ -n "$s" ] && { [ -z "$co" ] || [ "$s" -lt "$co" ]; }; then co=$s; fi
  [ -z "$co" ] && co=$(awk '/^btime/{print $2}' /proc/stat)   # last resort
  ```
  Caveat: the uploads anchor equals chat-open only when the chat begins with an
  upload — true for this workflow, where `unzip-project` consumes the import zip
  first. A chat that opens with text and uploads later anchors on the first upload;
  one with no uploads at all has no persistent anchor and falls back to a marker,
  then `btime`.

## current-container readings (max-with-floor)

`session_time` and `session_time_header` measure time on the live container:
```sh
b=$(awk '/^btime/{print $2}' /proc/stat)
s=$(stat -c %Y /home/claude/tmp_session_start 2>/dev/null || echo 0)
start=$(( s >= b ? s : b ))     # honor an explicit marker only if newer than boot; btime floor
now=$(date +%s); d=$((now - start))   # "Session time: $((d/60))m $((d%60))s"
```
The floor means a stale or missing marker can't skew it. These reset on restart by
design — they answer "time on the current container," not "since chat opened."

## wall-clock reading

`chat_time` uses the chat-open anchor `co` directly (no `btime` floor), so it keeps
counting across restarts:
```sh
# compute co as above
now=$(date +%s); d=$((now - co))
# "Chat time: $((d/3600))h $(((d%3600)/60))m $((d%60))s"
```

## showhotfs /mnt/project fallback uses the wall-clock anchor

`showhotfs` surfaces /mnt/project changes primarily by diffing against the imported
export zip's CONTENT (the chat-start snapshot) — no timestamp needed. Only when
there is no import zip does it fall back to mtimes, and that fallback uses the
**wall-clock chat-open anchor `co`, not `btime`**: a /mnt/project file with mtime ≥
`co` is "touched this chat." Using `co` is essential — an edit made *before* a
mid-chat restart has an mtime earlier than `btime`, so a `btime` cutoff would
WRONGLY miss it; `co` catches it. `btime` is only the deepest last resort (no
import zip AND empty uploads AND no marker). The timestamp fallback can only flag
"touched" — it cannot subclassify CREATED vs MODIFIED or detect DELETED, and a
flatten touches everything — so the zip content baseline stays strongly preferred.

## When a chat's container restarts mid-conversation

The compute container (kernel) and the working filesystem are decoupled — a restart
reboots the container (new `btime`) while `/home/claude` and `/mnt/user-data` files
persist with their original mtimes. Causes:

- **Context compaction** — the common case. A long conversation is summarized; the
  filesystem is restored (so uploads and `tmp_session_start` survive) but the
  container reboots, so `btime` jumps forward.
- **Idle teardown / resume** — stepping away long enough for the sandbox to be
  reclaimed; the next message spins up a fresh container with a new `btime`
  (persisted files may or may not return).
- **Infrastructure churn** — deploys, crashes, resource rebalancing, host moves.

Observed: `tmp_session_start` mtime 07:17 UTC against a 16:19 boot → a naive
marker-only reading reported ~554m (≈9h) wrong; the `btime` floor fixed
current-container readings, and the uploads anchor gives the true ~9h wall-clock.

## scripts/show_time.sh and reboot counting

`scripts/show_time.sh` prints both elapsed clocks at once — `now - chat_opened`
(wall-clock) and `now - container_booted` (session) — plus a count of container
reboots observed this chat. Reboots are counted by appending each distinct
`/proc/stat` btime to `/home/claude/.boot_history` (a dotfile that survives
compaction reboots and is excluded from exports) and counting distinct values.

Caveat: a reboot is only counted if `show_time.sh` or `session_time_header` runs
*after* it. `session_time_header` now appends `btime` to `.boot_history` every turn
(deduped), so once it is running each turn the count is **complete going forward**;
boots that happened *before* tracking began still can't be recovered (hence the
"(+ at least 1 before tracking began)" note). The history resets per chat.

Compactions are tracked separately and reliably — they are NOT the same as
reboots (a chat can reboot many times but compact zero or once). Each compaction
appends a `=== Journal Entry <ts> ===` line to `/mnt/transcripts/journal.txt` and
writes a timestamped transcript file. `show_time.sh` therefore reports:
- **compaction count** = journal entries (fallback: timestamped transcript files);
- **time since last compaction** = now − `journal.txt` mtime.
Observed: 1 compaction at 16:20 against ≥3 container boots — proof the two are
decoupled.

## What still reads current-container (`btime`) time, and why

- **`session_time`** and **`session_time_header`** — intentionally current-container:
  they report uptime of the live container and reset on restart. Use `chat_time`
  for wall-clock since chat open.
- **`showhotfs`** — `btime` is touched only in the deepest fallback (no import zip
  AND empty uploads AND no marker); its normal path is the zip content baseline and
  its mtime fallback uses the wall-clock anchor `co`.
- Nothing else.
