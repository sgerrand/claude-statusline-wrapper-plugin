# Claude plugin for wrapping statuslines

A plugin for [Claude Code](https://claude.com/code) that composes the
statuslines of multiple other plugins into a single `statusLine.command`
output.

Claude Code only accepts one `statusLine.command`. This wrapper sits in
that slot and fans out to as many sources (plugin scripts, inline
commands, anything readable on stdout) as you configure, joining their
outputs in declaration order with a configurable separator.

## Install

Install via the Claude Code plugin system, then point your settings at
the wrapper executable:

```jsonc
// ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/statusline-wrapper"
  }
}
```

If `${CLAUDE_PLUGIN_ROOT}` is not exported in your environment, use the
absolute path that `claude plugin list` reports for `statusline-wrapper`.

On first invocation the wrapper writes a starter config to
`~/.claude/statusline-wrapper.json` (or `${CLAUDE_CONFIG_DIR}/...`) with
zero sources. With no sources, the wrapper falls back to a built-in line
showing `<model> | <cwd-basename> | <ctx>% ctx` so you see something
immediately.

## Configure

Run `/statusline-wrapper:configure` from inside Claude Code for an
interactive setup that scans `~/.claude/plugins/cache/` for candidate
statusline scripts, lets you pick which to enable, and writes the
config atomically. If the `autoWireSettings` userConfig flag is `true`,
it also patches `~/.claude/settings.json` for you; otherwise it prints
the snippet to paste.

You can also edit `~/.claude/statusline-wrapper.json` directly:

```jsonc
{
  "version": 1,
  "separator": " | ",
  "defaultTimeoutMs": 200,
  "onError": "silent",          // silent | label | placeholder
  "fallback": "default",        // default | empty
  "sources": [
    {
      "id": "model",
      "label": "model",
      "command": "jq -r '.model.display_name // \"claude\"'",
      "order": 10,
      "passStdin": true
    },
    {
      "id": "git-branch",
      "label": "git",
      "command": "cwd=$(jq -r '.workspace.current_dir // .cwd // \"\"'); cd \"$cwd\" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null || true",
      "order": 20,
      "timeoutMs": 150
    }
  ]
}
```

A more complete annotated example, including a disabled entry that wraps
the [caveman](https://github.com/anthropics/claude-code-plugins) plugin's
statusline, lives at `examples/statusline-wrapper.json`.

### Source contract

Each source command:

- runs as `bash -c "<command>"`;
- receives the Claude Code statusline JSON on stdin (unless
  `passStdin: false`);
- must write its piece of the statusline to stdout (single line, ANSI +
  OSC 8 hyperlinks OK; output longer than `SW_MAX_BYTES` (default 4 KiB)
  is truncated, and embedded newlines are cut at the first one with a
  log warning);
- must finish within `timeoutMs` (default 200, falls back to
  `defaultTimeoutMs` when absent);
- empty stdout with exit 0 is treated as an intentional empty slot and
  silently dropped;
- non-zero exit is reported per `onError`:
  - `silent` (default) — slot omitted;
  - `label` — slot replaced with `[<label>:err]`;
  - `placeholder` — slot replaced with `?`.

Stderr from sources is appended to `~/.claude/statusline-wrapper.log`
(rotated at 64 KB) and never printed to the terminal. If the wrapper
itself cannot load its config (invalid JSON, non-numeric `timeoutMs`,
missing `jq`, symlinked config file, etc.) it prints a single
`[statusline-wrapper] config load failed — see <log>` line to stderr
and falls back to the built-in default source.

### Field reference

| Field | Default | Notes |
|---|---|---|
| `version` | required | currently `1` |
| `separator` | `" "` | string between source outputs |
| `defaultTimeoutMs` | `200` | applied when a source omits `timeoutMs`; must be a positive JSON number (string `"200"` is rejected) |
| `onError` | `"silent"` | `silent` \| `label` \| `placeholder`; unknown values are logged and downgraded to `silent` |
| `fallback` | `"default"` | when no sources produce output: `default` runs the built-in line; `empty` emits nothing; unknown values downgrade to `default` |
| `sources[].id` | required | stable identifier; used in log lines |
| `sources[].label` | falls back to `id` | rendered when `onError: label` |
| `sources[].command` | required | shell command run via `bash -c` |
| `sources[].order` | `0` | sparse integers (10, 20, …) recommended |
| `sources[].enabled` | `true` | set `false` to keep an entry without running it |
| `sources[].timeoutMs` | inherits `defaultTimeoutMs` | per-source ceiling; must be a positive JSON number |
| `sources[].passStdin` | `true` | `false` redirects the source's stdin to `/dev/null` |

## CLI flags

For debugging, the wrapper also accepts:

```sh
bin/statusline-wrapper --version   # prints the manifest version
bin/statusline-wrapper --diag      # prints config + environment diagnostics
bin/statusline-wrapper --help      # usage summary
```

`--diag` does not read stdin and does not run any source — safe to
invoke from a terminal when investigating a misconfigured statusline.

## How it runs

`bin/statusline-wrapper`:

1. tees Claude Code's JSON stdin into a temp file;
2. loads `~/.claude/statusline-wrapper.json` (writes a starter config if
   missing; refuses symlinks);
3. fans out enabled sources in parallel (`& … wait`), each bounded by
   `timeout`/`gtimeout` (and unbounded with a logged warning if neither
   is on PATH);
4. joins their captured stdouts in `order` with `separator`;
5. falls back to `lib/default-source.sh` when zero sources produce
   output and `fallback: default`.

Wall time is `max(source_i)`, not `sum`. Keep individual sources fast
(<50 ms) and avoid Node/Python cold starts on the render path.

## Tests

```sh
test/run.sh
```

Drives the wrapper end-to-end against the harness in `test/run.sh`.
Exits non-zero on any failure. CI (GitHub Actions, see
`.github/workflows/ci.yml`) runs `shellcheck -x` and the test suite on
both Ubuntu and macOS on every push and pull request.

## Status

Pre-1.0. Render path and `/statusline-wrapper:configure` are
implemented; output caching and `--rescan` are not.
