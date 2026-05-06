#!/usr/bin/env bash
# Composition: parallel fan-out of configured sources, joined by SW_SEPARATOR.
#
# Reads SW_SOURCES_TSV (set by config.sh) line-by-line, runs each command in
# the background with stdin teed from a shared file, then concatenates the
# captured outputs in declaration order.
#
# Caller must populate the SW_TMPS array; sw_compose appends its mktemp -d to
# it for cleanup by the entrypoint's EXIT trap.

# Picks an available timeout binary. Echoes the command name, or "" if none.
sw_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
  else
    echo ""
  fi
}

# sw_compose <stdin-file>
# Stdout: joined statusline (single line). Returns 0 on success, 1 if zero
# sources produced any output (caller decides whether to fall back).
sw_compose() {
  local stdin_file="$1"
  local tmpdir
  tmpdir=$(mktemp -d) || return 2
  SW_TMPS+=("$tmpdir")

  local timeout_cmd
  timeout_cmd=$(sw_timeout_cmd)
  if [[ -z "$timeout_cmd" ]]; then
    sw_log "no timeout binary on PATH; sources will run unbounded"
  fi

  local i=0
  local -a ids=() labels=()
  local id label command timeoutMs passStdin
  while IFS=$'\t' read -r id label command timeoutMs passStdin; do
    [[ -z "${command:-}" ]] && continue
    ids[i]="$id"
    labels[i]="$label"
    local timeout_s
    timeout_s=$(awk -v ms="${timeoutMs:-200}" 'BEGIN{ printf "%.3f", ms/1000 }')
    (
      local rc=0
      if [[ "$passStdin" == "1" ]]; then
        if [[ -n "$timeout_cmd" ]]; then
          "$timeout_cmd" "$timeout_s" bash -c "$command" <"$stdin_file" >"$tmpdir/$i.out" 2>>"$SW_LOG_PATH" || rc=$?
        else
          bash -c "$command" <"$stdin_file" >"$tmpdir/$i.out" 2>>"$SW_LOG_PATH" || rc=$?
        fi
      else
        if [[ -n "$timeout_cmd" ]]; then
          "$timeout_cmd" "$timeout_s" bash -c "$command" </dev/null >"$tmpdir/$i.out" 2>>"$SW_LOG_PATH" || rc=$?
        else
          bash -c "$command" </dev/null >"$tmpdir/$i.out" 2>>"$SW_LOG_PATH" || rc=$?
        fi
      fi
      printf '%s' "$rc" >"$tmpdir/$i.rc"
    ) &
    i=$((i + 1))
  done <<<"$SW_SOURCES_TSV"

  wait

  local -a parts=()
  local j rc out
  for ((j = 0; j < i; j++)); do
    rc=$(cat "$tmpdir/$j.rc" 2>/dev/null || echo 1)
    out=$(cat "$tmpdir/$j.out" 2>/dev/null || true)
    if [[ "$rc" != "0" ]]; then
      sw_log "source ${ids[j]} exit=$rc"
      case "${SW_ON_ERROR:-silent}" in
        label)       parts+=("[${labels[j]}:err]") ;;
        placeholder) parts+=("?") ;;
        *)           ;;
      esac
      continue
    fi
    [[ -z "$out" ]] && continue
    out="${out%$'\n'}"
    parts+=("$out")
  done

  if (( ${#parts[@]} == 0 )); then
    return 1
  fi

  local result="${parts[0]}"
  local k
  for ((k = 1; k < ${#parts[@]}; k++)); do
    result+="${SW_SEPARATOR}${parts[k]}"
  done
  printf '%s\n' "$result"
}
