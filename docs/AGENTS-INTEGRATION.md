# Local agent status

For account linking and browser sign-in, see [account connections](ACCOUNT-CONNECTIONS.md). Account identity and activity are separate connections.

Orbit reads bounded JSON files from `~/Library/Application Support/Orbit/agents/` every two seconds. Each producer writes a file atomically. The agent bridge stores a provider, session ID, project basename, status and timestamp. It deliberately discards prompt, output, transcript, command and tool-input content.

## Automatic local detection

**Settings → Connections → Local session activity** enables a read-only adapter for `~/.codex/sessions/**/*.jsonl` and `~/.claude/projects/**/*.jsonl`, respecting the active configuration-directory overrides. Existing activity-enabled providers have it enabled on upgrade. Account sign-in alone does not enable monitoring for a new installation.

The reader runs on a background actor. It discovers up to 64 recently changed files, polls appended data every two seconds and refreshes discovery every five seconds. Initial recovery reads a bounded tail (up to 8 MiB per file), with bounded lines and reads; it does not perform an unbounded historical scan. Incomplete lines wait for the next write, oversized or malformed lines are skipped, and replaced/truncated files reset their parser. Symlinks and non-regular files are excluded. Recent status exists only in memory and is dropped when monitoring is disabled.

The projection decodes lifecycle tags and times, session identity, project basename and model; message content is ignored except for content-block type tags that distinguish a tool result from a new prompt. Codex uses explicit task-start, complete and interruption records. Claude uses user/assistant metadata and stop reasons; subagents keep distinct IDs. Unsupported schemas yield no invented progress. Local records and hooks merge by session ID and event time, so a late old callback cannot replace newer completion. The compatibility adapter is version-sensitive; supported hooks remain available independently.

The notch shows the number of live agents, rotates their elapsed clocks and displays a twelve-second Done/Failed indication. Expanded views put active/waiting sessions ahead of recent results and usage. A session with no local activity for fifteen minutes becomes stale, not completed. A very long silent tool can therefore appear stale. If work began outside the recovery tail, fresh work is still shown, with an unknown elapsed time until an explicit start is available.

For a read-only device check, run `build/Orbit.app/Contents/MacOS/Orbit --inspect-local-activity`. This reports counts and elapsed times without printing prompts, replies or account information.

## Account activity hooks

**Enable activity** in a connected account card installs Orbit’s command entries in the provider’s active user configuration: `~/.codex/hooks.json` for Codex or `~/.claude/settings.json` for Claude Code by default. Provider configuration-directory overrides are respected. Existing JSON is backed up with owner-only permissions, unrelated settings and hook handlers are preserved, and repeated installation does not duplicate Orbit’s handlers. **Stop activity** removes only the exact Orbit command entries.

Codex hooks publish status for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, PreCompact, PostCompact, Stop, Interrupt, SessionEnd, SubagentStart and SubagentStop through `orbit-agent --codex-hook`. Claude uses its events listed below plus SubagentStart/SubagentStop. Child events get their own card and parent ID. Both helpers emit no output, never approve/deny tools, and exit successfully if malformed input or a write failure occurs.

Restart the provider’s sessions after connecting. Codex requires review and trust of the installed hooks in `/hooks`; Orbit never edits hook trust or disables protections. This covers supported sessions executing locally. Web chats, remote workers and cloud orchestration are not imported merely by signing in.

## Claude project-only connection

The **Connect a Claude project** button installs a command hook for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, StopFailure and SessionEnd in a project you select. It copies the bridge binary to a stable support-folder path and backs up existing JSON. This advanced project-only option leaves the global Claude configuration unchanged.

The hook reads the official event object from stdin, writes a status summary, emits no stdout, and exits successfully even if Orbit cannot write a status file. The hook never approves, denies or modifies tool execution. Restart the Claude Code session to load it.

To remove the connection, delete only the hook entries whose command invokes `orbit-agent --claude-hook` from that project’s `.claude/settings.local.json`. Restore the timestamped Orbit backup if no other settings have changed since installation. Remove its status card in Orbit separately.

## Codex CLI

The generated `orbit-codex` wrapper runs:

```sh
codex exec --json "$@" | orbit-agent --codex-stream
```

It sets `pipefail` and forwards every JSON line to stdout. Existing Codex CLI authentication and its own approval / sandbox defaults remain in effect. Use `ORBIT_CODEX_BIN=/absolute/path/to/codex` if it is not on PATH. It does not set an API key or start paid background tasks.

State is derived from `thread.started`, `turn.started`, `item.*`, `turn.completed`, `turn.failed` and `error` events. If the pipe ends without a terminal event, Orbit displays that explicitly. A producer that stops reporting for five minutes becomes **No recent update**; that does not mean it finished. A long silent model step can therefore show stale until the next event arrives.

Remove `orbit-codex` from Orbit’s support `bin/` folder to remove the wrapper. The advanced wrapper option leaves Codex user configuration unchanged.

## Any local producer

Send this schema to the bundled executable with `--agent-event`:

```json
{
  "id": "my-agent-session-id",
  "provider": "Local agent",
  "title": "Orbit",
  "detail": "Running tests",
  "phase": "running",
  "updatedAt": "2026-10-06T22:00:00Z",
  "progress": 0.5
}
```

Phases: `running`, `waiting`, `completed`, `failed`, `idle`, `offline`. Progress is optional and should be omitted unless the producer has a genuine measured denominator. Update timestamps while the producer is active; status files are not an authentication channel or a command execution interface.

```sh
build/Orbit.app/Contents/MacOS/Orbit --agent-event < status.json
```

IDs are hashed for filenames to prevent path traversal. Invalid, oversized or symbolic-link files are ignored. Status files are local and can be cleared with the card’s Dismiss action. The event bridge has no network listener, remote control or access to desktop conversation databases. Account linking uses the provider’s documented account interface separately; see the account guide.

Sources: [Codex lifecycle hooks](https://learn.chatgpt.com/docs/hooks), [Codex non-interactive JSON output](https://learn.chatgpt.com/docs/non-interactive-mode), [Claude Code hook inputs](https://code.claude.com/docs/en/hooks).

## Session metrics

`orbit-agent --claude-metrics` accepts the [official Claude status-line JSON](https://code.claude.com/docs/en/statusline#available-data), retains only display metadata in owner-only files under `agent-metrics/`, and prints a short default status line. Connect metrics preserves an existing status-line command by forwarding its JSON and keeping that command's output. It does not read the transcript path present in the payload. Disconnect restores the saved original configuration only when the installed status-line object has not been edited.

Model, context input/output counts, context percentage, reported API value and rate limits are optional. A metrics update does not imply that a task is running or finished. Readings show their timestamps. Codex plan usage is read separately through the authenticated app-server account interface and remains in memory.

Repair activity updates the installed bridge binary and completes missing Orbit handlers. It does not alter provider hook trust, unrelated handlers, approvals, sandboxing or existing logins.
