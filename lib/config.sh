#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034
# SW_SEPARATOR / SW_SOURCES_TSV / SW_*_MS look unused to shellcheck because
# they are consumed by lib/compose.sh after sourcing. Disabled file-wide.

# Config loader and logging helpers for statusline-wrapper.
#
# Sourced by bin/statusline-wrapper. Calling sw_load_config sets:
#   SW_CONFIG_PATH         absolute path to config file
#   SW_SEPARATOR           string between source outputs
#   SW_DEFAULT_TIMEOUT_MS  default per-source timeout in milliseconds
#   SW_ON_ERROR            silent | label | placeholder
#   SW_FALLBACK            default | empty
#   SW_SOURCES_TSV         tab-separated rows: id\tlabel\tcommand\ttimeoutMs\tpassStdin

SW_CONFIG_PATH="${SW_CONFIG_PATH:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-wrapper.json}"
SW_LOG_PATH="${SW_LOG_PATH:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-wrapper.log}"
SW_LOG_MAX_BYTES="${SW_LOG_MAX_BYTES:-65536}"

sw_log() {
  local msg="$*"
  if [[ -e "$SW_LOG_PATH" ]]; then
    local sz
    sz=$(stat -f%z "$SW_LOG_PATH" 2>/dev/null || stat -c%s "$SW_LOG_PATH" 2>/dev/null || echo 0)
    if (( sz > SW_LOG_MAX_BYTES )); then
      local lock="${SW_LOG_PATH}.lock"
      if [[ -d "$lock" && -z "$(find "$lock" -maxdepth 0 -mmin -1 2>/dev/null)" ]]; then
        rmdir "$lock" 2>/dev/null
      fi
      if mkdir "$lock" 2>/dev/null; then
        mv -f "$SW_LOG_PATH" "${SW_LOG_PATH}.1" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null
      fi
    fi
  fi
  printf '%s [statusline-wrapper] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$msg" >>"$SW_LOG_PATH" 2>/dev/null || true
}

sw_starter_config() {
  cat <<'JSON'
{
  "version": 1,
  "separator": " ",
  "defaultTimeoutMs": 200,
  "onError": "silent",
  "fallback": "default",
  "sources": []
}
JSON
}

sw_write_starter_if_missing() {
  if [[ ! -e "$SW_CONFIG_PATH" ]]; then
    mkdir -p "$(dirname "$SW_CONFIG_PATH")" 2>/dev/null || return 1
    sw_starter_config >"$SW_CONFIG_PATH" || return 1
    printf '[statusline-wrapper] wrote starter config to %s — run /statusline-wrapper:configure to add sources\n' "$SW_CONFIG_PATH" >&2
  fi
}

sw_load_config() {
  if ! sw_write_starter_if_missing; then
    sw_log "could not create starter config at $SW_CONFIG_PATH"
    return 1
  fi
  if [[ -L "$SW_CONFIG_PATH" ]]; then
    sw_log "refusing symlinked config: $SW_CONFIG_PATH"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    sw_log "jq not found on PATH"
    return 1
  fi
  if ! jq -e . "$SW_CONFIG_PATH" >/dev/null 2>&1; then
    sw_log "config is not valid JSON: $SW_CONFIG_PATH"
    return 1
  fi
  SW_SEPARATOR=$(jq -r '.separator // " "' "$SW_CONFIG_PATH")
  if ! SW_DEFAULT_TIMEOUT_MS=$(jq -er '
    (.defaultTimeoutMs // 200)
    | if type != "number" or . <= 0 then
        error("defaultTimeoutMs must be a positive number, got " + (. | tojson))
      else . end
  ' "$SW_CONFIG_PATH" 2>/dev/null); then
    sw_log "invalid defaultTimeoutMs in $SW_CONFIG_PATH"
    return 1
  fi
  if ! jq -e --argjson defaultT "$SW_DEFAULT_TIMEOUT_MS" '
    (.sources // [])
    | map(select(.enabled != false) | (.timeoutMs // $defaultT))
    | all(type == "number" and . > 0)
  ' "$SW_CONFIG_PATH" >/dev/null 2>&1; then
    sw_log "one or more source timeoutMs values are not positive numbers"
    return 1
  fi
  SW_ON_ERROR=$(jq -r '.onError // "silent"' "$SW_CONFIG_PATH")
  case "$SW_ON_ERROR" in
    silent|label|placeholder) ;;
    *)
      sw_log "unknown onError '$SW_ON_ERROR', defaulting to silent"
      SW_ON_ERROR="silent"
      ;;
  esac
  SW_FALLBACK=$(jq -r '.fallback // "default"' "$SW_CONFIG_PATH")
  case "$SW_FALLBACK" in
    default|empty) ;;
    *)
      sw_log "unknown fallback '$SW_FALLBACK', defaulting to default"
      SW_FALLBACK="default"
      ;;
  esac
  SW_SOURCES_TSV=$(jq -r --argjson defaultT "$SW_DEFAULT_TIMEOUT_MS" '
    (.sources // [])
    | map(select(.enabled != false))
    | sort_by(.order // 0)
    | .[]
    | [
        (.id // ""),
        (.label // .id // ""),
        (.command // ""),
        (.timeoutMs // $defaultT),
        (if .passStdin == false then "0" else "1" end)
      ] | @tsv
  ' "$SW_CONFIG_PATH")
}
