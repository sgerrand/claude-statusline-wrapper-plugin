---
description: Configure statusline-wrapper sources interactively
---

You are configuring the `statusline-wrapper` plugin for the current
user. Your goal is to produce a valid
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-wrapper.json` with an
ordered list of statusline sources, then optionally wire it into
`~/.claude/settings.json`.

## Discovery

Scan for candidate statusline scripts:

- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/*/*/hooks/*statusline*`
- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/*/*/bin/*statusline*`
- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/*statusline*`

Skip non-executable matches and any path that is a symlink. The
plugin-cache pattern uses content-hashed version directories — when you
record a candidate's command in the config, replace the hash component
with `*` (e.g.
`bash ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/caveman/caveman/*/hooks/caveman-statusline.sh`)
so it survives plugin upgrades.

## Flow

1. Read the existing config at
   `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-wrapper.json`. If the
   file is a symlink, refuse to proceed and tell the user (matches the
   wrapper's own check). If it does not exist, treat as a fresh
   install with zero sources.
2. Run discovery. Build a candidate list excluding any path already
   present in the config.
3. Show the user:
   - Currently-configured sources: `id`, `label`, `command`, `enabled`,
     `order`.
   - Newly-discovered candidates with suggested ids derived from the
     plugin directory name.
4. Use `AskUserQuestion` to:
   - Select which candidates to add.
   - For each, confirm or edit `id`, `label`, and `timeoutMs`.
   - Confirm or change the `separator` (default `" | "`).
5. Ask whether to remove or disable any currently-configured source.
6. Compute new `order` values: keep existing orders, assign new
   sources the next multiple of 10 above the current maximum.
7. Validate the new JSON with `jq -e .` before writing. If validation
   fails, do not write — show the user the parse error.
8. Atomic write: write to `<path>.tmp`, then `mv` to the final path,
   so a partial write cannot leave the wrapper unable to load its
   config.

## Wiring `statusLine.command`

Read
`pluginConfigs."statusline-wrapper".options.autoWireSettings` from
`~/.claude/settings.json`.

- **true**: update `statusLine.command` in `~/.claude/settings.json`
  to point at the wrapper executable. Use `${CLAUDE_PLUGIN_ROOT}` when
  available; otherwise look up the absolute path via
  `claude plugin list --json`. Preserve any existing `statusLine` keys
  (`type`, `padding`, `refreshInterval`).
- **false or missing**: do NOT modify `~/.claude/settings.json`. Print
  the exact JSON snippet the user should paste, including the
  resolved absolute path to `bin/statusline-wrapper`.

## Verification

After writing, verify by piping `test/fixtures/sample-stdin.json`
through the wrapper and showing the output, or by running
`test/run.sh` if the user has a working tree of this plugin checked
out.

## Constraints

- Always show a before/after summary of the config before writing.
- Never write to `~/.claude/settings.json` unless `autoWireSettings`
  is explicitly `true`.
- Validate JSON before writing.
- Refuse to operate on a symlinked config file.
