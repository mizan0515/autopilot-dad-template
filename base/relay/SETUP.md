# Relay setup

The relay is a separate .NET-based broker. It lives in its own repo (typically a
fork of a reference implementation like `cardgame-dad-relay`).

## Prerequisites

- .NET 8 SDK or later
- Git
- PowerShell 7.2+ (for status scripts)

## 1. Clone or fork the reference relay

```sh
# Example: fork cardgame-dad-relay to your own org, then clone
git clone https://github.com/<your-org>/<your-relay>.git D:\<your-relay>
```

Pick a path that this project can point at. Typical layouts:

- Windows: `D:\<your-relay>`
- macOS / Linux: `~/code/<your-relay>`

## 2. Build the relay CLI

```sh
cd D:\<your-relay>
dotnet build -c Release
```

The CLI binary typically lands at:
- `CodexClaudeRelay.Adapters.Cli/bin/Release/net8.0/codex-claude-relay.exe` (Windows)
- `CodexClaudeRelay.Adapters.Cli/bin/Release/net8.0/codex-claude-relay` (macOS/Linux)

Add that directory to your `PATH`, or symlink the binary into `~/.local/bin/`.

## 3. Create a profile for this project

The relay uses per-project profiles under `profiles/<project-slug>/`. Copy the
profile stub shipped with this template:

```sh
cp -r <this-project>/relay/profile-stub <your-relay>/profiles/<your-slug>
```

Then edit:
- `profile.json` → set the project slug, directive, bucket list
- `agent-identities.json` → rename `<slug>-autopilot-manager`, `<slug>-route-direct-codex`, etc.
- `broker.<slug>.json` → adjust token budgets and turn limits to this project's size
- `tool-registry.json`, `policy-registry.json` → add/remove tool classes as needed

## 4. Point this project at the relay

Edit `.autopilot/config.json` in this project:

```json
{
  "relay_repo_path": "D:\\<your-relay>"
}
```

The autopilot loop reads this path to resolve relay-side artifacts and status.

## 5. Verify

```sh
codex-claude-relay --version
codex-claude-relay profile list
```

If both succeed, relay is installed and this project should discover the profile.

## MCP pass-through (default enabled)

Relay profiles ship with MCP pass-through enabled by default. This means:

- When Codex invokes an MCP tool (e.g., Unity MCP, Claude Preview), the relay
  forwards the call through a shared broker so Claude Code sees the same reply.
- Turn packets record the MCP calls in `turn-{N}.yaml` under `evidence.mcp_calls`.
- If a call fails or times out, the relay raises an anomaly signal rather than
  silently dropping the data.

To disable pass-through for a specific profile, set `profile.json`:
```json
{
  "mcp_passthrough": false
}
```

## Fallback: user-bridged mode

If you skip relay install, DAD still works:
- Each agent produces a peer prompt body.
- User copy-pastes between Codex and Claude Code.
- No MCP pass-through (each agent's MCP state is local).
- No centralized token ceiling (each agent's budget is local).

This is the default when `relay_repo_path` is empty in `.autopilot/config.json`.
