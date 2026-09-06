# Codex Context Bar

Small native macOS menu-bar monitor for the current Codex context window.

It reads only:

```text
~/.codex/sessions/**/*.jsonl
```

The displayed context percentage is calculated from the newest Codex
`event_msg/token_count` record:

```text
last_token_usage.input_tokens / model_context_window
```

Build:

```bash
./build.sh
```

Install and enable login startup:

```bash
./install.sh
```

## What it shows

The menu-bar title is `CTX` plus a five-cell bar and a percentage, e.g.
`CTX ▰▰▱▱▱ 38%`. The dropdown lists, for the newest session: context percent
with used/window tokens, model, input and cached-input tokens, output tokens,
the window size, when the record was written, and the session file name.
`Refresh Now` (⌘R) and `Quit` (⌘Q) are at the bottom; refresh is otherwise
every 2 seconds.

Only the last 512 KiB of a session file is read — the interesting record is the
newest one, so the whole transcript is never parsed. Nothing leaves the
machine: there is no network code in the binary.

## Tests

```bash
./build.sh && ./tests/run.sh
```

`tests/run.sh` points the reader at `tests/fixtures/sessions` via
`CODEX_CONTEXT_BAR_ROOT` and asserts the exact percentage, the model name and
that a malformed line does not abort the scan. That env var exists for this —
unset in normal use, when `~/.codex/sessions` applies. CI runs it on every push.

## Requirements

macOS 13 or newer (`-mmacosx-version-min=13.0`), Apple clang. No dependencies
beyond Cocoa — the whole program is one 388-line `main.m` built by a 30-line
`build.sh`.

## Licence

MIT.
