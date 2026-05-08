#!/usr/bin/env bash
# End-to-end harness for bin/statusline-wrapper.
#
# Each test writes a config to a tmpdir, pipes the fixture JSON through the
# wrapper with that config, and compares stdout to an expected string.
# Stderr is suppressed so the starter-config bootstrap message does not
# leak into golden comparisons.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT/bin/statusline-wrapper"
FIXTURE="$ROOT/test/fixtures/sample-stdin.json"
FAKES="$ROOT/test/fakes"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# All cases share one fixture, which would collide on the cache key.
# Cases that exercise caching set SW_CACHE_TTL_S explicitly.
export SW_CACHE_TTL_S=0
export SW_CACHE_DIR="$TMP/cache"

PASS=0
FAIL=0

run() {
  local name="$1"
  local cfg_json="$2"
  local expected="$3"
  local cfg="$TMP/$name.json"
  printf '%s' "$cfg_json" >"$cfg"
  local actual
  actual=$(SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Like run, but also asserts that stderr contains a substring. Use for
# load-failure cases that should both fall back AND emit a diagnostic
# line.
run_with_stderr() {
  local name="$1"
  local cfg_json="$2"
  local expected_stdout="$3"
  local expected_stderr_substring="$4"
  local cfg="$TMP/$name.json"
  printf '%s' "$cfg_json" >"$cfg"
  local stdout_file="$TMP/$name.stdout"
  local stderr_file="$TMP/$name.stderr"
  SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" >"$stdout_file" 2>"$stderr_file"
  local actual_stdout actual_stderr
  actual_stdout=$(cat "$stdout_file")
  actual_stderr=$(cat "$stderr_file")
  if [[ "$actual_stdout" == "$expected_stdout" && "$actual_stderr" == *"$expected_stderr_substring"* ]]; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n  stdout expected: %q\n  stdout actual:   %q\n  stderr substring expected: %q\n  stderr actual:   %q\n' \
      "$name" "$expected_stdout" "$actual_stdout" "$expected_stderr_substring" "$actual_stderr"
    FAIL=$((FAIL + 1))
  fi
}

# Like run, but uses a config that already exists at a non-default path
# (skips the starter-config write step which would overwrite the file).
run_existing() {
  local name="$1"
  local cfg_path="$2"
  local expected="$3"
  local actual
  actual=$(SW_CONFIG_PATH="$cfg_path" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

run "empty-fallback" \
  '{"version":1,"separator":" | ","fallback":"default","sources":[]}' \
  'Opus 4.7 | foo | 42% ctx'

run "two-sources" \
  '{"version":1,"separator":" | ","sources":[
     {"id":"a","command":"echo hello","order":10},
     {"id":"b","command":"echo world","order":20}
   ]}' \
  'hello | world'

run "order-respected" \
  '{"version":1,"separator":" ","sources":[
     {"id":"x","command":"echo c","order":30},
     {"id":"y","command":"echo a","order":10},
     {"id":"z","command":"echo b","order":20}
   ]}' \
  'a b c'

run "error-silent" \
  '{"version":1,"separator":" | ","onError":"silent","sources":[
     {"id":"a","command":"echo first","order":10},
     {"id":"bad","command":"false","order":20},
     {"id":"c","command":"echo last","order":30}
   ]}' \
  'first | last'

run "error-label" \
  '{"version":1,"separator":" | ","onError":"label","sources":[
     {"id":"a","label":"A","command":"echo first","order":10},
     {"id":"bad","label":"BAD","command":"false","order":20},
     {"id":"c","label":"C","command":"echo last","order":30}
   ]}' \
  'first | [BAD:err] | last'

run "timeout-enforcement" \
  "$(printf '{"version":1,"separator":" ","onError":"label","sources":[
     {"id":"fast","label":"F","command":"echo fast","order":10},
     {"id":"slow","label":"S","command":"bash %s","order":20,"timeoutMs":100}
   ]}' "$FAKES/slow.sh")" \
  'fast [S:err]'

run "empty-output-omitted" \
  '{"version":1,"separator":" | ","sources":[
     {"id":"a","command":"echo first","order":10},
     {"id":"empty","command":"true","order":20},
     {"id":"c","command":"echo last","order":30}
   ]}' \
  'first | last'

run "passStdin-false" \
  "$(printf '{"version":1,"separator":" ","sources":[
     {"id":"with","command":"bash %s","passStdin":true,"order":10},
     {"id":"without","command":"bash %s","passStdin":false,"order":20}
   ]}' "$FAKES/has-stdin.sh" "$FAKES/has-stdin.sh")" \
  'got none'

run "ansi-preserved" \
  "$(printf '{"version":1,"separator":" ","sources":[
     {"id":"red","command":"bash %s","order":10},
     {"id":"plain","command":"echo plain","order":20}
   ]}' "$FAKES/ansi.sh")" \
  "$(printf '\033[31mRED\033[0m plain')"

run "disabled-source-skipped" \
  '{"version":1,"separator":" | ","sources":[
     {"id":"a","command":"echo first","order":10},
     {"id":"off","command":"echo nope","order":15,"enabled":false},
     {"id":"c","command":"echo last","order":20}
   ]}' \
  'first | last'

# Slice 1: A — defaultTimeoutMs as a string crashes --argjson; reject at
# load and fall back, with a stderr diagnostic.
run_with_stderr "defaultTimeoutMs-string-rejected" \
  '{"version":1,"defaultTimeoutMs":"200","sources":[{"id":"a","command":"echo hi","order":10}]}' \
  'Opus 4.7 | foo | 42% ctx' \
  'config load failed'

# Slice 1: B — per-source timeoutMs as a string is rejected at load.
run_with_stderr "source-timeoutMs-string-rejected" \
  '{"version":1,"sources":[{"id":"a","command":"echo hi","timeoutMs":"100","order":10}]}' \
  'Opus 4.7 | foo | 42% ctx' \
  'config load failed'

# Slice 1: A — zero or negative defaultTimeoutMs is rejected.
run_with_stderr "defaultTimeoutMs-zero-rejected" \
  '{"version":1,"defaultTimeoutMs":0,"sources":[{"id":"a","command":"echo hi","order":10}]}' \
  'Opus 4.7 | foo | 42% ctx' \
  'config load failed'

# Slice 1: C — malformed JSON triggers fallback + stderr line.
run_with_stderr "malformed-json-config" \
  '{not valid json' \
  'Opus 4.7 | foo | 42% ctx' \
  'config load failed'

# Slice 2: G — invalid onError downgrades to silent (failed source is
# omitted, surviving source still renders).
run "invalid-onError-falls-back-to-silent" \
  '{"version":1,"separator":" | ","onError":"warn","sources":[
     {"id":"a","command":"echo first","order":10},
     {"id":"bad","command":"false","order":20}
   ]}' \
  'first'

# Slice 2: J — fallback: empty produces no output when no source emits.
run "fallback-empty-emits-nothing" \
  '{"version":1,"fallback":"empty","sources":[]}' \
  ''

# Slice 3: E — multi-line source output is truncated at the first
# newline with a log warning.
run "multi-line-source-output-truncated" \
  "$(printf '{"version":1,"separator":" | ","sources":[
     {"id":"a","command":"bash %s","order":10},
     {"id":"b","command":"echo tail","order":20}
   ]}' "$FAKES/two-lines.sh")" \
  'first | tail'

# Slice 3: D — output exceeding SW_MAX_BYTES is truncated. Use a small
# cap so the test does not need to emit megabytes.
export SW_MAX_BYTES=8
run "byte-cap-truncates-output" \
  '{"version":1,"separator":" | ","sources":[
     {"id":"big","command":"printf %.0sA {1..50}","order":10},
     {"id":"tail","command":"echo end","order":20}
   ]}' \
  'AAAAAAAA | end'
unset SW_MAX_BYTES

# Slice 2: J — symlinked config file is refused, wrapper falls back to
# the default source and emits the diagnostic line.
ln -sf "$TMP/symlink-target.json" "$TMP/symlink.json"
printf '{"version":1,"sources":[]}' >"$TMP/symlink-target.json"
{
  symlink_stdout=$(SW_CONFIG_PATH="$TMP/symlink.json" SW_LOG_PATH="$TMP/log" \
    "$WRAPPER" <"$FIXTURE" 2>"$TMP/symlink.stderr")
  symlink_stderr=$(cat "$TMP/symlink.stderr")
}
if [[ "$symlink_stdout" == 'Opus 4.7 | foo | 42% ctx' \
      && "$symlink_stderr" == *"config load failed"* ]]; then
  printf 'PASS symlink-config-refused\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL symlink-config-refused\n  stdout: %q\n  stderr: %q\n' \
    "$symlink_stdout" "$symlink_stderr"
  FAIL=$((FAIL + 1))
fi

# Slice 8: K — cache hit serves the previously-cached output even after
# the config changes, until the TTL expires.
cache_dir="$TMP/cache-hit-test"
cfg="$TMP/cache-hit.json"
printf '%s' '{"version":1,"sources":[{"id":"a","command":"echo first","order":10}]}' >"$cfg"
first=$(SW_CACHE_TTL_S=10 SW_CACHE_DIR="$cache_dir" \
  SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
printf '%s' '{"version":1,"sources":[{"id":"a","command":"echo second","order":10}]}' >"$cfg"
second=$(SW_CACHE_TTL_S=10 SW_CACHE_DIR="$cache_dir" \
  SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
if [[ "$first" == "first" && "$second" == "first" ]]; then
  printf 'PASS cache-hit-serves-stale-within-ttl\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL cache-hit-serves-stale-within-ttl\n  first:  %q\n  second: %q\n' "$first" "$second"
  FAIL=$((FAIL + 1))
fi

# Slice 8: K — cache TTL=0 disables caching entirely.
cache_dir="$TMP/cache-disabled-test"
cfg="$TMP/cache-disabled.json"
printf '%s' '{"version":1,"sources":[{"id":"a","command":"echo first","order":10}]}' >"$cfg"
first=$(SW_CACHE_TTL_S=0 SW_CACHE_DIR="$cache_dir" \
  SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
printf '%s' '{"version":1,"sources":[{"id":"a","command":"echo second","order":10}]}' >"$cfg"
second=$(SW_CACHE_TTL_S=0 SW_CACHE_DIR="$cache_dir" \
  SW_CONFIG_PATH="$cfg" SW_LOG_PATH="$TMP/log" "$WRAPPER" <"$FIXTURE" 2>/dev/null)
if [[ "$first" == "first" && "$second" == "second" && ! -d "$cache_dir" ]]; then
  printf 'PASS cache-ttl-zero-disables-caching\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL cache-ttl-zero-disables-caching\n  first:  %q\n  second: %q\n  cache_dir exists: %s\n' \
    "$first" "$second" "$([[ -d $cache_dir ]] && echo yes || echo no)"
  FAIL=$((FAIL + 1))
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
