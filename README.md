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

The menu-bar title is a bar plus a percentage, e.g. `▰▰▰▱▱▱▱▱  38%`. The
dropdown lists the newest sessions with their own context usage, and clicking
one reveals the session file path. Refresh is every 2 seconds, and the read is
incremental — only the tail of a session file is parsed once it has been seen.

Nothing leaves the machine: there is no network code in the binary.

## Requirements

macOS 13 or newer (`-mmacosx-version-min=13.0`), Apple clang. No dependencies
beyond Cocoa — the whole program is one 306-line `main.m` built by a 30-line
`build.sh`.

## Licence

MIT.
