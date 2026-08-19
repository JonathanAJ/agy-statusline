# agy-statusline

A fast, adaptive status line for the [Antigravity CLI](https://antigravity.google/docs/cli/statusline/) (`agy`).

One `jq` pass, pure bash, zero dependencies beyond `jq` — and it degrades gracefully on malformed or missing input instead of erroring into your prompt.

```text
● ready │ 3.7 Flash·High │ ~/my-project │  main✚⇡2 │ █░░░░░░░░░ 14% 88k↑ 61k↓ │ ◔ 93%·6d11h Pro │ ▶1 ✦2 │ PLAN
```

## What it shows

| Segment | Meaning |
| --- | --- |
| `● ready` | Agent state — green `●` idle, magenta `✳` thinking, cyan `⚙` working, blue `⚒` tool use |
| `3.7 Flash·High` | Active model, compacted (`Gemini 3.7 Flash (High)` → `3.7 Flash·High`) |
| `~/my-project` | Working directory, `~`-shortened, last two path components |
| ` main✚⇡2⇣1` | Git branch; `✚` dirty, `⇡`/`⇣` commits ahead/behind upstream (live `git` check) |
| `█░░░░░░░░░ 14%` | Context window usage bar — green → yellow → orange → red as it fills |
| `88k↑ 61k↓` | Total input/output tokens, humanized |
| `⚠200k` | Bold red badge when the conversation exceeds 200k tokens |
| `◔ 93%·6d11h Pro` | Your **tightest** quota bucket, time until it resets, and plan tier |
| `▶1 ⛓2 ✦3 ▣sbx` | Background tasks, subagents, artifacts, sandbox — only shown when active |
| `PLAN` | Execution mode (bold magenta in planning mode) |
| `[INSERT]` | Vim mode, when enabled |

## Adaptive layout

The status line reshapes itself to `terminal_width` from the payload:

- **≥ 120 cols** — everything on one line
- **85–119 cols** — two lines (state/model/git/context/quota on top; dir/tokens/badges below)
- **< 85 cols** — compact essentials: state, branch, context %, quota

## Requirements

- Antigravity CLI
- [`jq`](https://jqlang.org) (`brew install jq` / `apt install jq`)
- bash 3.2+ (works with macOS's stock bash)

## Install

```bash
git clone https://github.com/tweibley/agy-statusline.git
cd agy-statusline
./install.sh
```

The installer copies `statusline.sh` to `~/.gemini/antigravity-cli/`, makes it executable, and merges the `statusLine` block into your `settings.json` (backing up the original first). Restart `agy` to see it.

### Manual install

```bash
cp statusline.sh ~/.gemini/antigravity-cli/statusline.sh
chmod +x ~/.gemini/antigravity-cli/statusline.sh
```

Then add to `~/.gemini/antigravity-cli/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.gemini/antigravity-cli/statusline.sh"
  }
}
```

Optional `statusLine` keys supported by Antigravity: `padding` (blank lines above), `enabled` (toggle), `stack_with_default` (render below the built-in line).

## Try it without installing

The CLI pipes a JSON state payload to the script's stdin and renders its stdout. A sample payload is included:

```bash
./statusline.sh < examples/payload.json
```

## Customization

Everything is plain bash near the top of `statusline.sh`:

- **Colors** — the `palette` section defines all 256-color codes (tuned for dark themes)
- **Thresholds** — context bar turns yellow at 50%, orange at 75%, red at 90%; quota goes yellow ≤ 50%, red ≤ 20%
- **Bar width** — `barw=10`
- **Layout breakpoints** — the `WIDTH` checks at the bottom

## How it works

Antigravity re-runs the command whenever agent state changes, piping a JSON payload (model, context window, quota, VCS, counters, terminal width) to stdin. The script parses every field in a single `jq` call joined on the ASCII unit separator (so empty fields survive), then assembles ANSI-colored segments. See the [official statusline docs](https://antigravity.google/docs/cli/statusline/) for the full payload schema.

## License

[MIT](LICENSE)
