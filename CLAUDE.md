# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin that takes the single `statusLine.command` slot and
multiplexes it across many user-configured sources. End-user docs are in
`README.md` — this file is for working *on* the plugin.

## Commands

- `test/run.sh` — runs every end-to-end case; exits non-zero on any
  failure. Each case writes a config to a tmpdir, pipes
  `test/fixtures/sample-stdin.json` through `bin/statusline-wrapper` with
  `SW_CONFIG_PATH` and `SW_LOG_PATH` overridden, and asserts stdout
  equality. There is no single-test runner; copy a `run "..."` block out
  of `test/run.sh` to iterate on one case.
- No build step, no lint config.

## Architecture

The render path is bash + jq, on purpose: Claude Code invokes the
statusline after every assistant message and per `refreshInterval`, so
~30–60 ms node/python cold starts would dominate. Stay in bash unless
something genuinely cannot be expressed there.

Four-file pipeline, sourced left-to-right:

1. **`bin/statusline-wrapper`** — entrypoint, the path
   `statusLine.command` points at. Tees stdin to a temp file, sources
   `lib/config.sh` then `lib/compose.sh`, dispatches.
2. **`lib/config.sh`** — sets `SW_*` vars from
   `~/.claude/statusline-wrapper.json` (path overridable via
   `SW_CONFIG_PATH`). Also owns `sw_log` (rotated at 64 KB), the starter
   config, and the symlink refusal check.
3. **`lib/compose.sh`** — `sw_compose` runs each enabled source in a
   background subshell (`&`), bounded by `timeout`/`gtimeout`, captures
   stdout to `$tmpdir/$i.out` and exit code to `$tmpdir/$i.rc`, then
   joins in declaration order.
4. **`lib/default-source.sh`** — standalone fallback used when there are
   zero enabled sources or every source is empty/errored and `fallback:
   default`.

### Config-to-runtime contract

`config.sh` emits sources as **tab-separated** rows in
`SW_SOURCES_TSV`:

```
id<TAB>label<TAB>command<TAB>timeoutMs<TAB>passStdin(0|1)
```

`compose.sh` consumes them with `while IFS=$'\t' read -r ...`. Tabs
inside `command` would split the row — currently no commands need them,
but if you change the schema, keep the boundary explicit.

### Cleanup

The entrypoint owns a single EXIT trap (`sw_cleanup`) that `rm -rf`s
every path in the `SW_TMPS` array. Helpers append their own `mktemp -d`
to `SW_TMPS` rather than installing their own traps — bash `RETURN`
traps are global, not function-scoped, so per-function traps clobber
each other.

## Non-obvious gotchas

- **jq's `//` operator falls through on `false`, not just `null`.**
  `(.passStdin // true)` coerces an explicit `false` back to `true`. Use
  `if .passStdin == false then ... end` for any boolean field where the
  user might explicitly opt out. (Already bit us once — see commit
  `102ea2d`.)
- **`((i++))` returns 1 when `i` was 0**, which `set -e` treats as
  failure. Use `i=$((i + 1))` in code that lives under `set -e`.
- **`"${arr[*]}"` joins with the first character of `IFS` only.**
  `SW_SEPARATOR` is multi-character (` | ` is the common case), so
  `compose.sh` builds the joined string with an explicit loop instead of
  `IFS=$SW_SEPARATOR`.
- **Source stderr must never reach the terminal** — it would corrupt
  the prompt line. All `bash -c "$command"` invocations redirect
  `2>>"$SW_LOG_PATH"`. Preserve that.
- **`stat`** flags differ between BSD (macOS) and GNU. The log rotator
  in `config.sh` tries `-f%z` then `-c%s`. Mirror that pattern if you
  add another size check.
- **Log rotation uses a `mkdir`-based mutex** at `${SW_LOG_PATH}.lock`
  (atomic on every POSIX fs, no `flock` dependency). Stale locks older
  than one minute are reaped before claiming. If a wrapper crashes
  mid-rotate the next invocation cleans up; we do not hold the lock
  during the actual append, only during the `mv`.
- **`passStdin: false` redirects to `/dev/null`** — and an empty stdout
  with exit 0 is *intentionally* dropped (treated as "this source had
  nothing to say"), not flagged as an error. Tests using this pattern
  must assert via a fake that *prints* something, not via absence.
- **Numeric fields must be JSON numbers, not strings.**
  `defaultTimeoutMs` and per-source `timeoutMs` are validated at config
  load via `jq -er` with a `type == "number" and . > 0` guard. A string
  `"200"` is rejected, the wrapper logs and falls back to the default
  source, and `bin/statusline-wrapper` prints `[statusline-wrapper]
  config load failed — see <log>` to stderr.

## Testing pattern

`test/run.sh` is a single bash file with a `run` helper. Each case is
self-contained: a JSON config string, the expected stdout, no shared
state. New tests go inline. `test/fakes/` holds the minimum number of
real scripts (currently three) — only add a fake when an inline
`bash -c` would be unreadable or non-portable.

The fixture (`test/fixtures/sample-stdin.json`) is the JSON Claude Code
sends — keep it minimal but realistic. If you need to test a different
JSON shape, create a second fixture rather than mutating this one.

## Commit conventions

Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`,
`chore:`, optional `(scope)`). No `Co-Authored-By` trailers. Subject
imperative, ≤72 chars. See `git log` for the established voice.
