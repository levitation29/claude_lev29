#!/usr/bin/env bash
# time_compare — compare btime / session_time / chat_time in one pass.
#
#   btime         : current-container boot epoch from /proc/stat (resets on restart).
#   session_time  : CURRENT-CONTAINER elapsed. start = max(btime, mtime of
#                   /home/claude/tmp_session_start if present). btime floor means
#                   a stale/absent marker can't skew it below container uptime.
#   chat_time     : WALL-CLOCK since chat opened. anchor co = earliest immutable
#                   mtime in /mnt/user-data/uploads/ (NO btime floor, so it
#                   survives mid-chat restarts); falls back to tmp_session_start,
#                   then btime, only if uploads/ is empty.
#
# Prints a labeled comparison plus the raw anchors so the divergence is explicit.

set -u

now=$(date -u +%s)
btime=$(awk '/^btime/{print $2}' /proc/stat)

# session anchor
marker=/home/claude/tmp_session_start
if [ -f "$marker" ]; then
    smk=$(stat -c %Y "$marker"); marker_state="$smk ($(date -u -d @$smk '+%F %T') UTC)"
else
    smk=0; marker_state="ABSENT"
fi
sess_start=$(( smk >= btime ? smk : btime ))

# chat anchor: earliest immutable uploads/ mtime; fallbacks if uploads/ empty
co=""
if ls /mnt/user-data/uploads/* >/dev/null 2>&1; then
    co=$(for f in /mnt/user-data/uploads/*; do stat -c %Y "$f"; done | sort -n | head -1)
    co_src="earliest uploads/ mtime"
fi
if [ -z "$co" ]; then
    if [ -f "$marker" ]; then co=$smk; co_src="tmp_session_start (uploads/ empty)";
    else co=$btime; co_src="btime (uploads/ empty, no marker)"; fi
fi

fmt(){ local d=$1; printf '%dh %dm %ds' $((d/3600)) $(((d%3600)/60)) $((d%60)); }

bt_d=$((now - btime))
se_d=$((now - sess_start))
ch_d=$((now - co))

echo "now         : $now  ($(date -u -d @$now '+%F %T') UTC)"
echo "btime       : $btime  ($(date -u -d @$btime '+%F %T') UTC)"
echo "session mk  : $marker_state"
echo "chat anchor : $co  ($(date -u -d @$co '+%F %T') UTC)  [$co_src]"
echo
printf '%-26s %s\n' "btime uptime"  "$(fmt $bt_d)"
printf '%-26s %s\n' "Session time" "$(fmt $se_d)  [current-container, start=max(btime,marker)]"
printf '%-26s %s\n' "Chat time"    "$(fmt $ch_d)  [wall-clock, anchor=co, no btime floor]"
echo
# Divergence note
gap=$((ch_d - se_d))
if [ "$gap" -gt 60 ]; then
    echo "Note: chat_time exceeds session_time by $(fmt $gap) — a container restart"
    echo "      occurred mid-chat; session/btime reset, wall-clock chat_time did not."
elif [ "$smk" -eq 0 ]; then
    echo "Note: tmp_session_start marker ABSENT, so session_time == btime uptime."
    echo "      Run touch_start to lay the marker (btime floor still applies)."
else
    echo "Note: session_time and chat_time are aligned (no restart detected this chat)."
fi
