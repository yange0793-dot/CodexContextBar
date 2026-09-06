#!/bin/sh
# Asserts the reader against a fixture session, so the numbers the menu bar shows
# are checked rather than just compiled. Both assertions below are regressions we
# actually shipped:
#   1. millisecond timestamps failed to parse, so the FIRST token_count in a file
#      won instead of the newest — the bar froze at the session's opening size;
#   2. the model name was read off token_count, which never carries it, so the
#      menu always said "Codex".
set -eu
cd "$(dirname "$0")/.."
BIN=build/CodexContextBar.app/Contents/MacOS/CodexContextBar
[ -x "$BIN" ] || { echo "build first: ./build.sh" >&2; exit 1; }

out=$(CODEX_CONTEXT_BAR_ROOT="$PWD/tests/fixtures/sessions" "$BIN" --once)
fail=0
expect() {
  if printf '%s\n' "$out" | grep -qF "$1"; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    echo "      expected to contain: $1"
    fail=1
  fi
}

# 68000/272000 = 25%. The fixture's earlier record is 40800 (15%); seeing 15%
# means newest-record selection broke again.
expect 'Codex context: 25% (68000 / 272000 tokens)' 'newest token_count wins (ms timestamps parse)'
# Present only on a turn_context record, never on token_count.
expect 'Model: gpt-5.6-sol'                         'model comes from turn_context, not the fallback'
# The fixture's last line is deliberately not JSON.
expect 'rollout-fixture.jsonl'                      'malformed trailing line does not abort the scan'

if [ "$fail" -eq 0 ]; then echo; echo "all reader assertions passed"; else echo; echo "reader assertions FAILED" >&2; fi
exit "$fail"
