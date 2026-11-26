#!/usr/bin/env bash
# deslop-please's hook for coding agents (Claude Code, Codex, Cursor, pi, agy).
#
#   check.sh session-start [cursor|agy]  remember the Rust files of the project's workspace
#   check.sh stop [cursor|agy]           if they changed since, run deslop-please, and if
#                                        it reports errors, hand them back to the agent
#
# A stop checks only what changed since the last check in this session, so a
# turn that touched no Rust code is never held up, and one that is blocked
# but changes nothing more is let go. Errors listed in `.deslop-please.allow`
# at the workspace's root are known debt and do not block.
# Anything missing (no cargo, no deslop-please, no Cargo workspace) lets the
# stop through.
#
# Errors are handed back as Claude Code and Codex take them: exit 2 with the
# report on stderr. With `cursor`, as Cursor takes them: exit 0 with
# `{"followup_message": <report>}` on stdout. With `agy`, as Antigravity takes
# them: exit 0 with `{"decision": "continue", "reason": <report>}` on stdout.
#
# Reads the hook's JSON on stdin for its session (`session_id`, Cursor's
# `conversation_id`, or Antigravity's `conversationId`), and the project from
# CLAUDE_PROJECT_DIR, CURSOR_PROJECT_DIR, stdin's `cwd`/`workspacePaths`, else
# the current directory.

set -u

mode=${1:-stop}
agent=${2:-}
input=$(cat)

allow() {
    if [ "$agent" = agy ]; then
        if [ "$mode" = session-start ]; then
            printf '{}\n'
        else
            printf '{"decision": "allow"}\n'
        fi
    fi
    exit 0
}

if [ "$agent" = agy ] && [ "$mode" = stop ]; then
    reason=$(printf '%s' "$input" |
        sed -n 's/.*"terminationReason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)
    if [ -n "$reason" ] && [ "$reason" != NO_TOOL_CALL ]; then
        allow
    fi
fi

project_dir="${CLAUDE_PROJECT_DIR:-${CURSOR_PROJECT_DIR:-}}"
if [ -z "$project_dir" ]; then
    project_dir=$(printf '%s' "$input" |
        sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)
fi
if [ -z "$project_dir" ]; then
    project_dir=$(printf '%s' "$input" |
        sed -n 's/.*"workspacePaths"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)
fi
cd "${project_dir:-.}" 2>/dev/null || allow
command -v cargo >/dev/null 2>&1 || allow
manifest=$(cargo locate-project --workspace --message-format plain 2>/dev/null) || allow
root=$(dirname "$manifest")

session=$(printf '%s' "$input" |
    sed -n -e 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        -e 's/.*"conversation_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        -e 's/.*"conversationId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1 | tr -cd 'A-Za-z0-9_-')
state_dir="${CLAUDE_PLUGIN_DATA:-${PLUGIN_DATA:-${TMPDIR:-/tmp}/deslop-please-hook}}"
mkdir -p "$state_dir" 2>/dev/null || allow
state="$state_dir/${session:-session}-$(printf '%s' "$root" | cksum | cut -d ' ' -f 1)"

# The Rust files under the workspace's root, by content; build output and
# version control left out.
fingerprint() {
    find "$root" \( -name target -o -name .git \) -prune -o -type f -name '*.rs' -exec cksum {} + 2>/dev/null |
        sort | cksum
}

# $1 as a JSON string. The report has no control characters but newlines and
# tabs: it is printed without color.
json_string() {
    printf '%s' "$1" | awk '
        BEGIN { ORS = "" ; print "\"" }
        {
            gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
            if (NR > 1) print "\\n"
            print
        }
        END { print "\"" }'
}

now=$(fingerprint)
if [ "$mode" = session-start ]; then
    printf '%s\n' "$now" >"$state"
    allow
fi
if [ -f "$state" ] && [ "$(cat "$state")" = "$now" ]; then
    allow
fi
printf '%s\n' "$now" >"$state"

command -v deslop-please >/dev/null 2>&1 || allow
allow_file="$root/.deslop-please.allow"
arguments=()
[ -f "$allow_file" ] && arguments=(--allow "$allow_file")
errors="$state.stderr"
report=$(cd "$root" && CARGO_TERM_COLOR=never deslop-please ${arguments[@]+"${arguments[@]}"} 2>"$errors")
status=$?
case $status in
    0)
        allow
        ;;
    1)
        message="deslop-please reports structural errors in the Rust workspace at $root.
Fix them from first principles, as the deslop-please skill describes, and
related ones together; never only move code so an error disappears, and
never add entries to .deslop-please.allow unless the user asks for it.

$report"
        if [ "$agent" = cursor ]; then
            printf '{"followup_message": %s}\n' "$(json_string "$message")"
            exit 0
        fi
        if [ "$agent" = agy ]; then
            printf '{"decision": "continue", "reason": %s}\n' "$(json_string "$message")"
            exit 0
        fi
        printf '%s\n' "$message" >&2
        exit 2
        ;;
    *)
        # It could not run: tell the user, do not hold up the stop.
        printf 'deslop-please could not check %s:\n' "$root" >&2
        cat "$errors" >&2
        if [ "$agent" = agy ]; then
            printf '{"decision": "allow"}\n'
        fi
        exit 1
        ;;
esac
