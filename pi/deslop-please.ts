// deslop-please for pi. It runs `hooks/check.sh`, the hook Claude Code, Codex
// and Cursor run: at session start it remembers the workspace's Rust files,
// and before the agent settles it checks them if they changed. When
// deslop-please reports errors, they go back to the agent as a message and the
// agent goes on, at most MOST_FOLLOW_UPS times per prompt. The script lets a
// stop through when nothing changed since its last check, so an agent that
// cannot or will not fix them is not held up forever either way.

import { spawn } from "node:child_process"
import { randomUUID } from "node:crypto"
import { homedir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

const SCRIPT = fileURLToPath(new URL("../hooks/check.sh", import.meta.url))
const STATE = join(homedir(), ".pi", "agent", "deslop-please")
const MOST_FOLLOW_UPS = 5

interface Run {
  code: number | null
  stderr: string
}

/** `check.sh <mode>` for the project at `cwd`, in `session`. */
function check(mode: "session-start" | "stop", cwd: string, session: string): Promise<Run> {
  return new Promise((resolve) => {
    const child = spawn(SCRIPT, [mode], {
      cwd,
      env: { ...process.env, CLAUDE_PROJECT_DIR: cwd, CLAUDE_PLUGIN_DATA: STATE },
      stdio: ["pipe", "ignore", "pipe"],
    })
    let stderr = ""
    child.stderr.setEncoding("utf8")
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk
    })
    child.on("error", (error) => resolve({ code: null, stderr: String(error) }))
    child.on("close", (code) => resolve({ code, stderr: stderr.trim() }))
    child.stdin.end(JSON.stringify({ session_id: session }))
  })
}

export default function deslopPlease(pi: ExtensionAPI) {
  const session = randomUUID()
  let followUps = 0

  pi.on("session_start", async (_event, ctx) => {
    await check("session-start", ctx.cwd, session)
  })

  pi.on("before_agent_start", async (event) => {
    if (event.messageType === "user") followUps = 0
  })

  pi.on("agent_before_settle", async (event, ctx) => {
    if (followUps >= MOST_FOLLOW_UPS) return
    const run = await check("stop", ctx.cwd, session)
    if (run.code === 2) {
      followUps += 1
      return {
        entries: [
          ...event.entries,
          { type: "custom_message", customType: "deslop-please", content: run.stderr, display: true },
        ],
        continue: true,
      }
    }
    if (run.code !== 0 && run.stderr) ctx.ui.notify(run.stderr, "warning")
  })
}
