# CLI login guide — Claude Code + Codex

The autopilot loop runs either `claude` (Claude Code desktop CLI) or `codex` (Codex desktop CLI) under the hood. BOOTSTRAP Step 2 verifies at least one of them exists and is logged in. This guide covers first-time login for each.

## At a glance

| CLI | Install | Auth command | Token lifetime |
|---|---|---|---|
| Claude Code desktop | Comes with the desktop app (https://claude.com/claude-code) | Auto — open the desktop app once while signed into Anthropic | Tied to desktop session |
| Claude Code CLI only | `npm i -g @anthropic-ai/claude-code` (if you don't use the desktop app) | `claude login` → opens browser → OAuth → paste code back | ~30 days idle |
| Codex desktop | Comes with the desktop app (https://chatgpt.com/codex) | Auto via desktop | Tied to desktop session |
| Codex CLI only | `npm i -g @openai/codex` | `codex auth login` → opens browser → OAuth → paste code back | ~30 days idle |

Only **one** of the two needs to be logged in for the loop to run. BOOTSTRAP prefers `claude` if both are available.

## Claude Code desktop (recommended on Windows/macOS)

1. Download Claude Code from https://claude.com/claude-code and install.
2. Launch the desktop app and sign in with your Anthropic account (browser OAuth). Once you see the chat window, the `claude` CLI is logged in too.
3. Verify from a terminal:

   ```
   claude --version
   claude "say hi"      # one-shot prompt — should respond without prompting for login
   ```

If step 3 prompts for login, the CLI is not picking up the desktop session — quit the desktop app once, relaunch, and try again.

## Claude Code CLI-only (headless machines / CI)

```
npm i -g @anthropic-ai/claude-code
claude login
```

`claude login` prints a URL; open it in any browser, complete OAuth, and paste the callback code back into the terminal. On headless servers, copy the URL to a local browser — the callback code is a short string you paste back. Verify with `claude --version` and `claude "say hi"`.

## Codex desktop

1. Download Codex from https://chatgpt.com/codex.
2. Launch and sign in with your OpenAI / ChatGPT account.
3. Verify:

   ```
   codex --version
   codex exec "say hi"
   ```

## Codex CLI-only

```
npm i -g @openai/codex
codex auth login
```

Same OAuth browser flow as Claude. Verify with `codex exec "say hi"`.

## Common failures

- **"command not found: claude" (or codex)** — the CLI isn't on your PATH. On Windows, restart your shell after installing the desktop app. On macOS with Homebrew, try `brew doctor`.
- **"invalid session" / "please log in again"** — the token expired. Re-run `claude login` or `codex auth login`.
- **Corporate proxy blocks OAuth callback** — use the CLI-only variant from a personal machine first, confirm the token is cached (`~/.claude/` or `~/.codex/`), then copy the token file to the corporate machine.
- **Two accounts in the desktop app** — the CLI picks whichever is currently signed in. Switch accounts in the desktop app and re-test.

## Which CLI does BOOTSTRAP use?

BOOTSTRAP Step 2 runs both `claude --version` and `codex --version`. The first one that exits zero wins. The `.autopilot/config.json` key `autopilot_ai` records the choice. To switch, edit that key and re-run `.autopilot/runners/preflight.ps1 -Ai <claude|codex>`.

## Security notes

- Both CLIs cache a long-lived OAuth refresh token under your user profile (`~/.claude/` or `~/.codex/`). Do **not** commit that directory.
- `.autopilot/` is the operational directory for this repo — it is already in `.gitignore` for the token cache paths, but verify: the autopilot loop must never add `claude.json` or `codex.json` from your home directory to the staging area.
- If you rotate credentials, re-run `claude login` / `codex auth login`. The loop picks up the new token on the next iter.
