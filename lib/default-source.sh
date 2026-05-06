#!/usr/bin/env bash
# Default fallback source. Reads JSON on stdin, writes one line:
#   "<model> | <cwd-basename> | <ctx>% ctx"
# Used when the user has zero configured sources or every source fails and
# fallback=default is set.

set -euo pipefail

input=$(cat)
model=$(jq -r '.model.display_name // "claude"' <<<"$input")
cwd=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

cwd_base=""
[[ -n "$cwd" ]] && cwd_base=$(basename "$cwd")

out="$model"
[[ -n "$cwd_base" ]] && out+=" | $cwd_base"
[[ -n "$ctx" ]] && out+=" | ${ctx}% ctx"
printf '%s\n' "$out"
