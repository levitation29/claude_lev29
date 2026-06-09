#!/usr/bin/env bash
# show_time.sh — report two elapsed clocks plus container-reboot count.
#
#   now - chat_opened    : wall-clock since the chat opened (survives restarts)
#   now - container_boot : time on the current live container (resets each restart)
#   reboots this chat    : distinct container boots observed (see caveat below)
#
# Chat-open anchor = earliest immutable mtime in /mnt/user-data/uploads/ (the first
# thing you sent), else tmp_session_start, else container boot.
#
# Reboot count: each container boot has a distinct /proc/stat btime. We append every
# btime we see to a dotfile that persists across compaction reboots, and count the
# distinct values. CAVEAT: a reboot is only counted if this script (or another
# recorder) runs after it, so the count is a LOWER BOUND and only covers boots seen
# since tracking began. session_time_header now appends btime every turn (deduped) for full coverage; see
# session_time_header). Resets per chat (the dotfile lives in /home/claude scratch).
set -uo pipefail

BOOT_HISTORY="${BOOT_HISTORY:-/home/claude/.boot_history}"
now=$(date +%s)
b=$(awk '/^btime/{print $2}' /proc/stat)

# --- wall-clock chat-open anchor (persists across reboots) ---
co=$(find /mnt/user-data/uploads -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1 | cut -d. -f1)
s=$(stat -c %Y /home/claude/tmp_session_start 2>/dev/null || echo)
if [ -n "$s" ] && { [ -z "$co" ] || [ "$s" -lt "$co" ]; }; then co="$s"; fi
[ -z "$co" ] && co="$b"

# --- record this boot; count distinct boots observed ---
touch "$BOOT_HISTORY" 2>/dev/null || true
grep -qx "$b" "$BOOT_HISTORY" 2>/dev/null || echo "$b" >> "$BOOT_HISTORY"
boots=$(sort -nu "$BOOT_HISTORY" 2>/dev/null | grep -c .)
[ "$boots" -lt 1 ] && boots=1
reboots=$((boots - 1))
# did the chat open before the earliest boot we recorded? then >=1 reboot predates tracking
earliest_boot=$(sort -n "$BOOT_HISTORY" 2>/dev/null | head -1)
pre=""
[ -n "$earliest_boot" ] && [ "$co" -lt "$earliest_boot" ] && pre=" (+ at least 1 before tracking began)"

# --- chat compactions (each writes a journal entry + a timestamped transcript) ---
JDIR=/mnt/transcripts
compactions=0; last_compact=""
if [ -f "$JDIR/journal.txt" ]; then
  compactions=$(grep -c '=== Journal Entry' "$JDIR/journal.txt" 2>/dev/null)
  last_compact=$(stat -c %Y "$JDIR/journal.txt" 2>/dev/null)
fi
if [ "${compactions:-0}" -eq 0 ]; then          # fallback: count timestamped transcripts
  compactions=$(ls "$JDIR"/*.txt 2>/dev/null | grep -vc journal.txt)
  last_compact=$(ls -t "$JDIR"/*.txt 2>/dev/null | grep -v journal.txt | head -1 | xargs -r stat -c %Y 2>/dev/null)
fi

fmt() { local t=$1; printf '%dh %dm %ds' $((t/3600)) $(((t%3600)/60)) $((t%60)); }
dc=$((now - co)); ds=$((now - b))

printf 'now              : %s\n' "$(TZ=America/Denver date -d @$now  +'%Y-%m-%d %H:%M:%S %Z')"
printf 'chat opened      : %s\n' "$(TZ=America/Denver date -d @$co   +'%Y-%m-%d %H:%M:%S %Z')"
printf 'container booted  : %s\n' "$(TZ=America/Denver date -d @$b    +'%Y-%m-%d %H:%M:%S %Z')"
echo
printf '\xe2\x8f\xb1 now - chat opened      (wall-clock): %s\n' "$(fmt $dc)"
printf '\xe2\x8f\xb1 now - container booted (session)   : %s\n' "$(fmt $ds)"
printf '\xe2\x86\xbb container reboots this chat        : %s%s   [distinct boots seen: %s]\n' "$reboots" "$pre" "$boots"
if [ -n "$last_compact" ] && [ "${compactions:-0}" -gt 0 ]; then
  dk=$((now - last_compact))
  printf '\xe2\x9c\x82 chat compactions this chat         : %s   (last: %s ago)\n' "$compactions" "$(fmt $dk)"
else
  printf '\xe2\x9c\x82 chat compactions this chat         : 0   (not compacted yet)\n'
fi
