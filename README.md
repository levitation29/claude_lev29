**My Claude.ai stuff**

do_acid will work with just command_2.notes or command_2_preferences.notes
but the full ACID protocol needs claude_acid_2.notes
I'm going to update the do_acid in command_2.notes to get claude_acid_2.notes from this repo if not findable in a current claude chat.
claude should be able to figure that out and the right raw.github url will be in the do_acid definition in command_2*

command_2_preferences.notes should always be just the stripped down (no comments) version of command_2.notes for pasting into user preferences

has efficient "Conventions" style of getting multiple behaviors with less language, plus nice iterate language
I may reduce these as I understand what I really ant


From your preferences (I copy/paste the contents of command_2_preferences.notes into my account preference text box)
every defined shortcut in command_2*
 
**Claude Shortcut Commands**
 
---
 
**Describe**
 
| Command | Description |
|---|---|
| `describe-behavior` | One-sentence job, capability bullets with specific numbers, CLI flags, line count + deps. Reads code directly — doesn't trust docstrings. |
| `describe-structure` | Entry point, call hierarchy, state machines, exception flow, external interfaces. Flags docstring divergence; groups workarounds by root cause. |
| `describe-structure-deep` | Same as `describe-structure` but exhaustive: every workaround, its constraint, shared-root siblings, and what a clean design would look like. |
 
---
 
**Plan**
 
| Command | Description |
|---|---|
| `plan-review-api` | API expert review: surface area, naming, defaults, error contracts. No edits. |
| `plan-simplify-silent` | Cut overspecified/redundant/speculative/duplicate content; collapse, generalize, drop; iterate until further cuts lose load-bearing content. No commentary. |
| `simplify-plan` | `plan-simplify-silent` + report line count and what was cut. |
| `simplify-plan-deeper` | `simplify-plan` ×3 max if cuts were made. |
| `plan-score` | Score 5 categories × sub-metrics (1–5): API quality, implementation clarity, test coverage, risk management, doc quality. Identifies highest-leverage changes. Includes comparison table if prior version exists. |
 
---
 
**Filesystem**
 
| Command | Description |
|---|---|
| `showskillfs` | `ls` `/mnt/skills/{public,examples,user}/` |
| `showtranscriptfs` | `ls` `/mnt/transcripts/` |
| `showprojectfs` | `ls` `/mnt/project` |
| `showuserfs` | `ls` `/home/claude/`, `outputs/`, `uploads/`, `tool_results` |
| `showmyfs` | `showuserfs` + `showskillfs` + `showtranscriptfs` + `showprojectfs` |
| `mtime_output` | List `outputs/` files with MDT mtimes. |
| `mtime_claude` | List `/home/claude/` files with MDT mtimes. |
| `touch_start` | `touch /home/claude/tmp_session_start`; `mtime_output` |
| `session_time` | Diff from `tmp_session_start` to now as `Session time: Xm Ys` |
| `touch_chat_start` | `touch outputs/tmp_chat_start`; `mtime_output` *(orphaned; prefer `touch_start`)* |
| `chat_time` | Diff from `outputs/tmp_chat_start` as `Chat time: Xm Ys` |
| `session_time_header` | Silently at start of every response: print `⏱ Session: Xm Ys`; skip if file missing. |
 
---
 
**Output Modifiers**
 
| Command | Description |
|---|---|
| `dont_narrate_fixes` | No fix narration. |
| `skip_post-round_summary` | No post-round summary. |
| `no_fix_list` | No fix list before presenting files. |
| `showme` | Present modified output files with MDT mtimes. |
| `showmeall` | Present all output files with MDT mtimes. |
| `jump-to-bottom` | Jump to bottom of streaming text. |
| `cleanstop` | If clean (no fixes made), stop. Else `showme`; `jump-to-bottom`. |
 
---
 
**Single-Shot**
 
| Command | Description |
|---|---|
| `review` | Report all issues, no fixes. |
| `linesme` | Report total line count. |
| `timeout_sleep_ints` | Verify timeout/sleep vars are integers. No-op for files without them. |
| `fiximportant` | Fix topmost remaining issue from the issue list. |
| `sequential-fixes` | `fiximportant`; `cleanstop`, else `fiximportant` again ×10 max. |
| `rewrite` | (1) `timeout_sleep_ints` (2) `fix-rewrite-keepcomments-silent` (3) `linesme` |
| `otf` | Confirm one-true-file rule is active. No ACID machinery. |
| `do_acid` | Fetch `claude_acid_2.md` if missing (from GitHub), snapshot all `/home/claude/` files lacking one, register default invariants, confirm. Follow SNAPSHOT/EDIT/PUBLISH/RESTORE per that file. |
| `trim_for_preferences` | Read `command_2.notes` (uploads or working path); produce condensed paste-ready version; save as `command_2_preferences.notes` and publish to outputs. |
 
---
 
**Workers**
 
Workers are exhaustive single-pass functions invoked by pipeline families or directly.
 
| Command | Description |
|---|---|
| `fix-silent` | Fix all bugs silently. |
| `fix-broad-silent` | `fix-silent` + style, naming, comments, dead code. |
| `fix-security-silent` | Fix injection, privilege, leakage, unsafe patterns silently. |
| `fix-perf-review-silent` | Perf expert review, flag issues, then `sequential-fixes`. |
| `fix-api-review-silent` | API expert review, flag issues, then `sequential-fixes`. |
| `md-update-silent` | Update `.md` with impl details (esp. error handling), then `sequential-fixes`. |
| `schema-update-silent` | Update `.schema` with full SQL behavior range, then `sequential-fixes`. |
| `fix-rewrite-silent` | Rewrite unclean sections, no commentary. |
| `fix-rewrite-keepcomments-silent` | Same, preserve all comments. |
 
---
 
**Pipeline Families**
 
Invoke as `<family>` (defaults to `max=1`) or `<family> max=N`.  
Pattern: (1) `timeout_sleep_ints` (2) worker (3) final step (4) if `max>1`: `cleanstop`, else repeat up to `max−1` more times.
 
| Family | Worker | Final Step | Max Cap |
|---|---|---|---|
| `fix` | `fix-silent` | `linesme` | 5 |
| `broad` | `fix-broad-silent` | `linesme` | 5 |
| `security` | `fix-security-silent` | `linesme` | 5 |
| `perf_review` | `fix-perf-review-silent` | `showme` | 4 |
| `api_review` | `fix-api-review-silent` | `showme` | 4 |
| `md_update` | `md-update-silent` | `showme` | 4 |
| `schema` | `schema-update-silent` | `showme` | 4 |
 
---
 
**Counters**
 
| Command | Description |
|---|---|
| `session_counts` | Read/increment `/home/claude/.session_counts`, print `🔢 Turn N · tool calls so far: C` |
| `session_counts_header` | Silently run `session_counts` at start of every response; skip if file unwritable. |
| `session_counts_resync T C` | Write `T C` to `.session_counts` directly. Both args required. |

