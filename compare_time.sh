#!/usr/bin/env bash
# compare_time.sh — show every "start" anchor side-by-side with its elapsed time,
# so the different clocks (wall-clock vs current-container vs compaction) are
# directly comparable. Also records the current boot (like show_time.sh /
# session_time_header) so the reboot counter advances.
set -uo pipefail

TZ_OUT='America/Denver'
BOOT_HISTORY="${BOOT_HISTORY:-/home/claude/.boot_history}"
JDIR=/mnt/transcripts
now=$(date +%s)
b=$(awk '/^btime/{print $2}' /proc/stat)

# record this boot (dedup)
touch "$BOOT_HISTORY" 2>/dev/null || true
grep -qx "$b" "$BOOT_HISTORY" 2>/dev/null || echo "$b" >> "$BOOT_HISTORY"

# --- anchors ---
up=$(find /mnt/user-data/uploads -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1 | cut -d. -f1)
mk=$(stat -c %Y /home/claude/tmp_session_start 2>/dev/null || echo)
# wall-clock chat-open = earliest of uploads / marker, else btime
co="$up"; { [ -n "$mk" ] && { [ -z "$co" ] || [ "$mk" -lt "$co" ]; }; } && co="$mk"
[ -z "$co" ] && co="$b"
# compaction signals
firstc=""; lastc=""
if [ -f "$JDIR/journal.txt" ] && grep -q '=== Journal Entry' "$JDIR/journal.txt" 2>/dev/null; then
  lastc=$(stat -c %Y "$JDIR/journal.txt" 2>/dev/null)
fi
oldest_t=$(ls -tr "$JDIR"/*.txt 2>/dev/null | grep -v journal.txt | head -1)
[ -n "$oldest_t" ] && firstc=$(stat -c %Y "$oldest_t" 2>/dev/null)
[ -z "$lastc" ] && [ -n "$oldest_t" ] && lastc=$(stat -c %Y "$(ls -t "$JDIR"/*.txt 2>/dev/null | grep -v journal.txt | head -1)")
compactions=$(grep -c '=== Journal Entry' "$JDIR/journal.txt" 2>/dev/null || echo 0)
[ "${compactions:-0}" -eq 0 ] && compactions=$(ls "$JDIR"/*.txt 2>/dev/null | grep -vc journal.txt)
boots=$(sort -nu "$BOOT_HISTORY" 2>/dev/null | grep -c .); [ "$boots" -lt 1 ] && boots=1
reboots=$((boots-1))

el() { local s=$1; [ -z "$s" ] && { printf '   —'; return; }; local t=$((now-s)); printf '%dh %02dm %02ds' $((t/3600)) $(((t%3600)/60)) $((t%60)); }
when() { [ -z "$1" ] && { printf '%-19s' '(none)'; return; }; printf '%-19s' "$(TZ=$TZ_OUT date -d @"$1" +'%Y-%m-%d %H:%M:%S')"; }

printf 'now: %s %s\n\n' "$(TZ=$TZ_OUT date -d @$now +'%Y-%m-%d %H:%M:%S')" "$(TZ=$TZ_OUT date +%Z)"
printf '%-26s %-19s %-14s %s\n' 'anchor' 'when (MDT)' 'elapsed' 'clock'
printf '%-26s %-19s %-14s %s\n' '--------------------------' '-------------------' '--------------' '-----'
printf '%-26s %s %-14s %s\n' 'chat opened (uploads)'   "$(when "$up")"  "$(el "$up")"  'wall-clock (HUD-like)'
printf '%-26s %s %-14s %s\n' 'tmp_session_start marker' "$(when "$mk")"  "$(el "$mk")"  'raw marker (may be stale)'
printf '%-26s %s %-14s %s\n' 'wall-clock anchor (co)'   "$(when "$co")"  "$(el "$co")"  'used by chat_time'
printf '%-26s %s %-14s %s\n' 'first compaction'         "$(when "$firstc")" "$(el "$firstc")" 'transcript/journal'
printf '%-26s %s %-14s %s\n' 'last compaction'          "$(when "$lastc")"  "$(el "$lastc")"  'time-since-compression'
printf '%-26s %s %-14s %s\n' 'container booted (btime)' "$(when "$b")"   "$(el "$b")"   'current-container (session)'
echo
printf 'compactions this chat : %s\n' "${compactions:-0}"
printf 'container reboots seen : %s   [distinct boots: %s]\n' "$reboots" "$boots"
echo
# divergence: how much of the chat predates the current container
gap=$(( (now-co) - (now-b) ))   # = b - co
if [ "$gap" -gt 0 ]; then
  printf 'wall-clock - session   : %dh %02dm %02ds  (a container restart occurred mid-chat: session/btime reset, wall-clock did not)\n' $((gap/3600)) $(((gap%3600)/60)) $((gap%60))
else
  printf 'wall-clock - session   : 0h 00m 00s  (no restart yet: this container has been up since the chat opened)\n'
fi
if [ -n "$lastc" ]; then
  printf 'compaction − session   : %dh %02dm %02ds  (last compaction was this long before the current boot; +/- => reboot since/before compaction)\n' $(( (b-lastc)/3600 )) $(( ((b-lastc)%3600)/60 )) $(( (b-lastc)%60 ))
fi
echo
echo 'note: the Claude debug HUD session time anchors at the browser conversation start,'
echo '      so it tracks the wall-clock row (chat opened), NOT container booted.'
