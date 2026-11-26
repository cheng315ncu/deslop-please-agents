# deslop-please-agents

Makes coding agents use [deslop-please](https://github.com/deterministic-machines/deslop-please), the linter for **deep** modules and **narrow** interfaces in Rust, on their own while they work. It supports Claude Code, Codex, Cursor, pi and Antigravity (`agy`).

Each agent gets three things:

- **A skill** on when to run `deslop-please` and how to fix what it reports from first principles. Agents never mute errors by writing `.deslop-please.allow`; that stays your decision.
- **A check when the agent finishes.** If the turn changed Rust code, the check runs `deslop-please`. If it reports errors, the agent gets them back and keeps working. Errors listed in `.deslop-please.allow` at the workspace root don't count. A turn that touched no Rust code is never held up. If the agent changes nothing more after being blocked, it's allowed to stop.

## Requirements

`deslop-please` 0.1.6 or later, and `rust-analyzer`, both on `PATH`:

```bash
cargo install --git https://github.com/deterministic-machines/deslop-please deslop-please --locked
```

## Install

### Claude Code

```
/plugin marketplace add cheng315ncu/deslop-please-agents
/plugin install deslop-please@cheng315ncu
```

### Codex

```bash
codex plugin marketplace add cheng315ncu/deslop-please-agents
codex plugin add deslop-please@cheng315ncu
```

Codex runs a plugin's hooks only once you trust them. Open `/hooks` in Codex and trust deslop-please's `SessionStart` and `Stop` hooks.

### pi

```bash
pi install git:github.com/cheng315ncu/deslop-please-agents
```

### Antigravity (`agy`)

```bash
agy plugin install https://github.com/cheng315ncu/deslop-please-agents
```

### Cursor

The repo is a Cursor plugin (`.cursor-plugin/`). Without the plugin, add the pieces yourself:

- **Hooks:** add the entries of `hooks/cursor-hooks.json` to `~/.cursor/hooks.json`, with `${CURSOR_PLUGIN_ROOT}` replaced by where this repo is.
- **Skill:** link `skills/deslop-please` into `~/.cursor/skills/`.

## Existing debt

If a workspace already has many errors, the check blocks every turn that touches Rust. To accept the existing errors as a baseline, run this once at the workspace root yourself:

```bash
deslop-please --update-allow .deslop-please.allow
```

## How it is put together

All five agents share one hook script, `hooks/check.sh`, which needs only bash:

- `session-start` records a fingerprint of the workspace's `.rs` files.
- `stop` runs `deslop-please` only if that fingerprint changed since the last check in the session.
- On errors it hands the report back: exit 2 with the report on stderr for Claude Code and Codex, exit 0 with `{"followup_message": …}` on stdout for Cursor (`check.sh stop cursor`), or exit 0 with `{"decision": "continue", "reason": …}` on stdout for Antigravity (`check.sh stop agy`).
- If deslop-please can't run, the agent isn't blocked and you're told why.

| Agent | Manifest | Hooks |
|---|---|---|
| Claude Code | `.claude-plugin/` | `hooks/hooks.json` |
| Codex | `.codex-plugin/`, `.agents/plugins/marketplace.json` | `hooks/hooks.json` |
| Antigravity (`agy`) | `.antigravity-plugin/` | `hooks.json` |
| Cursor | `.cursor-plugin/` | `hooks/cursor-hooks.json` |
| pi | `package.json` | `pi/deslop-please.ts`: runs `check.sh` at `session_start` and `agent_before_settle`, at most 5 rounds per prompt |

The skill runs `deslop-please --json` through the agent's shell. In Claude Code, allow it once so it runs without a prompt: add `"Bash(deslop-please:*)"` to `permissions.allow` in `~/.claude/settings.json`.

## License

MIT. deslop-please itself is by Deterministic Machines, Inc., under the MIT license.
