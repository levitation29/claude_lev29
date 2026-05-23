# claude_acid_2.md

ACID discipline for Claude's file edits via `view` / `str_replace` / `cp`.
Snapshot/restore semantics so a failed edit can't leave a file in an
unrecoverable state.

---

## 1. The one-true-file rule

Three paths, three roles, one-directional flow:

```
/mnt/user-data/uploads/<f>  →  /home/claude/<f>  →  /mnt/user-data/outputs/<f>
   (source, read-only)         (working path,         (published,
                                edit here only)        copy here at publish)
```

- The working path is the only live copy for the entire session.
- Never edit the outputs copy.
- Never `cp` from outputs back to the working path — a stale copy can
  clobber the live one.
- Never re-copy from uploads after first touch — same reason.

A fourth path, `/home/claude/.<f>.acid_snapshot`, holds the rollback
record beside the working path. It's auxiliary: never read or written
by anything outside this protocol.

---

## 2. Definitions

- **Working path.** `/home/claude/<basename>`.
- **Snapshot.** `/home/claude/.<basename>.acid_snapshot`. Hidden by
  the leading dot.
- **Edit cycle.** The sequence of `str_replace` calls from one
  snapshot to whichever ends the cycle next: a successful PUBLISH
  (which refreshes the snapshot) or a RESTORE (from any failure). A
  cycle can contain zero edits.
- **First touch.** The first `view`, `bash_tool` read, or `str_replace`
  of a path under `/mnt/user-data/uploads/` in the session. Fires once
  per file. Mentions in the conversation without access don't count.
- **Publish.** The full check-copy-refresh sequence in §4 PUBLISH —
  invariant evaluation, `cp` working → outputs, and snapshot refresh.
  Triggered automatically before `present_files`, or explicitly via
  `acid_publish`. The only way the user sees Claude's edits.

---

## 3. ACID, mapped onto file edits

| ACID | Meaning | Threat |
|---|---|---|
| **A**tomicity | Either the change is in, or the file is restored to the start of the edit cycle. | A `str_replace` failing partway through a multi-edit logical change. |
| **C**onsistency | After publish, the file satisfies its invariants. | An edit that succeeds textually but breaks syntax or violates a registered check. |
| **I**solation | Outputs never reflects mid-edit state. | Presenting before invariants pass; `cp`-ing from outputs back. |
| **D**urability | Published state is reproducible from the working path. | Working path and outputs diverging silently. |

---

## 4. The protocol

The working path is the live file; the snapshot is the rollback record;
outputs is a read-replica that updates only after invariants pass.

### SNAPSHOT (automatic on first touch; explicit via `acid_snapshot`)

1. **Establish working path** if not present:
   `cp /mnt/user-data/uploads/<f> /home/claude/<f>`. If it already
   exists, reuse it — never re-copy from uploads, which would clobber
   session edits.
2. **Snapshot:** `cp /home/claude/<f> /home/claude/.<f>.acid_snapshot`.
   Single overwriting `cp`; the snapshot is never absent.
3. **Register invariants** (defaults + any custom checks). See below.

Files Claude creates (`create_file`, `bash_tool`) are their own working
path; snapshot immediately after creation.

### EDIT (each `str_replace` within a cycle)

- **`view` the working path immediately before every `str_replace`.**
  Earlier `view` output in context may have drifted; `old_str` must be
  grounded in current bytes.
- `str_replace` on the working path only. Never on snapshot or outputs.
- A failed `str_replace` (no-match, multi-match) doesn't modify the
  file. On failure: if prior edits in this cycle succeeded, RESTORE
  first to undo them. Then end the cycle and report. Don't patch
  around the error.

### PUBLISH (automatic before `present_files`; explicit via `acid_publish`)

1. **Evaluate invariants.** Any failure → RESTORE; skip steps 2–3.
2. **Publish:** `cp /home/claude/<f> /mnt/user-data/outputs/<f>`.
3. **Refresh snapshot:** single overwriting `cp` working → snapshot.

A file is "edited since the last publish" iff its working path differs
from its snapshot (`cmp -s` returns nonzero). Auto-publish (before
`present_files`) runs steps 1–3 only on files matching that condition;
unchanged files are skipped. On invariant failure, auto-publish halts
the response from presenting; explicit publish reports the failure and
lets the response continue.

### RESTORE (automatic on failure; explicit via `acid_restore`)

1. `cp /home/claude/.<f>.acid_snapshot /home/claude/<f>` — working path
   returns to start-of-cycle state.
2. **Keep the snapshot** until the next SNAPSHOT overwrites it.
3. Outputs untouched. Report what failed; don't auto-retry.

### Invariants

Registered at SNAPSHOT, evaluated at PUBLISH via `bash_tool` exit code
(0 = pass).

Defaults:
- *Syntax*, if a checker is known for the extension: `.py` →
  `python -m py_compile`; `.js` → `node --check`; `.json` →
  `python -c 'import json,sys; json.load(open(sys.argv[1]))'`. Other
  extensions get no syntax check.
- *Sanity floor:* file must not be empty.

Custom checks (via `acid_snapshot <f> check "<rule>"`) are free-text
rules Claude evaluates by re-reading the file. Inherently advisory —
phrase them so any reasonable evaluation reaches the same verdict
("no line contains 'TODO'", not "code is well-structured").

### Basename collisions

If two source files share a basename, disambiguate with a suffix
(`<f>.1`, `<f>.2`) for working path, snapshot, and outputs.

### Session scope

All state lives under `/home/claude/`, reset between tasks.

### Error reporting

All protocol-level errors (failed `str_replace`, failed invariant,
failed `cp`, missing prerequisite for a shorthand verb) are reported
to the user as a single chat-output line in this format:

```
[acid] <verb-or-step>: <reason> (file: <basename>)
```

Examples: `[acid] EDIT: str_replace no-match (file: foo.py)`,
`[acid] PUBLISH: invariant 'syntax' failed, exit 1 (file: foo.py)`,
`[acid] acid_restore: no snapshot exists (file: bar.md)`. Reports
appear inline in the response, not in a log file. No structured-data
channel; the format is for humans.

### Filesystem failures

The protocol assumes `cp`, `rm`, and `bash_tool` invocations succeed.
If one fails (disk full, permission denied, missing path), Claude
does not advance to the next step: working path, snapshot, and
outputs remain at their pre-call state, and the failure is reported
in the error format above. The protocol does not attempt recovery.

---

## 5. Shorthand surface

Three optional verbs; the default flow needs none of them.

- `acid_snapshot <file> [check "<rule>"...]` — force a fresh snapshot;
  optionally register custom checks (repeat `check "<rule>"` per rule).
  Establishes the working path from uploads if not yet touched.
- `acid_publish <file>` — publish now without waiting for
  `present_files`. On invariant failure, restore and report; the
  response continues.
- `acid_restore <file>` — roll back to the snapshot. Snapshot is kept.

Missing prerequisites (no working path, no snapshot, no upload) are
errors with no state change, reported in the §4 error format.

The user's filesystem visibility is `/mnt/user-data/outputs/` only.
Working paths and snapshots live in `/home/claude/`, inspectable via
the `showmyfs` shorthand (`ls -la` on `/home/claude/`, outputs, and
uploads).

---

## 6. Known failure modes to guard against

- Skipping the pre-edit `view` on back-to-back edits, treating a
  just-written `new_str` as ground truth.
- Grabbing `old_str` from stale `view` output in context after edits
  invalidated it.
- Including the `    N\t` line-number prefix from `view` output in
  `old_str` (display-only; causes a no-match).
- Editing `/mnt/user-data/uploads/` directly, or accidentally
  `view`-ing or editing the outputs path instead of the working path.
- Pipeline loops (`fix max=2`, `broad max=3`, etc.) where the
  discipline holds on the first iteration but slips on later ones.
- Non-unique `old_str` — a fresh `view` doesn't fix it; widen the
  snippet until unique.
