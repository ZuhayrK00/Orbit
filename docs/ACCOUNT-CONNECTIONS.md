# Account connections

Orbit can link the account used by Codex or Claude Code on the current Mac. Open **Settings → Connections → Connect account**. If the provider is already signed in, Orbit shows its account identity and plan. Otherwise, the provider opens its browser sign-in. Orbit confirms connection only after the provider reports an authenticated account.

This is a local companion integration. It does not import every conversation associated with an email address, access ordinary web chats, or discover remote cloud jobs.

## What powers it

| Provider | Sign-in and account information | Local activity |
| --- | --- | --- |
| Codex | Official Codex app-server account methods over a private stdin/stdout process. Codex manages browser login and credential storage. | Read-only local session lifecycle metadata, plus optional documented hooks for approval events. The older JSON event wrapper remains available. |
| Claude Code | Official `claude auth status --json` and `claude auth login --claudeai`. Claude Code manages browser login and credential storage. | Read-only local session lifecycle metadata, plus optional documented hooks for approval events. |

References: [Codex account integration](https://learn.chatgpt.com/docs/app-server#authentication), [Claude CLI authentication commands](https://code.claude.com/docs/en/cli-reference), [Codex hooks](https://learn.chatgpt.com/docs/hooks), [Claude Code hooks](https://code.claude.com/docs/en/hooks).

## User flow

1. Choose **Connect account** on the provider card. Orbit checks for an installed provider tool. Codex can also be found inside supported installed ChatGPT/Codex app bundles.
2. Existing provider sign-ins are recognised. Otherwise, finish the provider’s browser login. A pending browser page does not count as connected; cancellation, errors and timeouts remain visible.
3. Check the displayed account and plan. No API key entry is required for subscription sign-ins. An already-configured API/provider credential is labelled separately; Orbit does not replace it automatically.
4. Turn on **Local session activity** to detect work from the provider’s local session records, including sessions already open. Existing installations that already enabled Orbit activity retain that opt-in on upgrade. No provider restart or hook approval is needed for this read-only detection.
5. **Enable activity** also installs optional hooks for approval requests and explicit lifecycle callbacks. Those hooks require provider reload; Codex additionally requires review in `/hooks`. Orbit does not change hook trust or bypass that review.

**Refresh account** checks the sign-in again. Linked accounts are checked once per minute while Orbit is running, and restored on app launch. **Unlink account** stops Orbit’s account checks and clears its in-memory account display; it does not log the provider out. **Stop activity** disables local monitoring and removes Orbit’s global hook entries. The local-session toggle can separately stop the read-only reader. Previously installed project-specific hooks remain under the project’s control.

## Usage and connection health

Codex subscription accounts also show usage windows and their reset times from `account/rateLimits/read`. Each returned bucket is displayed separately; missing values are not treated as unused quota. Refresh usage retries a failed read without signing out. Orbit does not redeem resets or buy credits.

Claude Code 2.1.286 or later can also supply fresh plan limits through a bounded, control-only `get_usage` request. Orbit initializes a provider process with no prompt, tools, MCP, hooks or session persistence, then closes it after the read. Successful reads are limited to once a minute; unavailable versions/failed requests retain the local-sample fallback. This is a version-gated CLI compatibility interface, not a guaranteed stable public API. The protocol and cancellation are fixture-tested; live support depends on the installed Claude version and account.

For Claude, choose **Connect metrics** to connect the official status-line JSON feed. Orbit preserves an existing command and its output, and stores an owner-only restoration record under `Orbit/connections/`. The next Claude status update can report model, context token counts, context percentage, plan limits and an estimated API value. Some fields are absent until the provider supplies them; that estimate is not the subscription bill. **Disconnect metrics** restores the original status-line object, refusing to overwrite subsequent user edits. This connection is separate from activity and account identity.

Already-installed bridge executables update with Orbit at launch, without changing hook definitions. **Repair activity** appears when handlers are incomplete or that update could not complete. Repair preserves unrelated provider configuration and creates a backup. Restart the provider and review changed Codex hooks in `/hooks`. The card separately shows whether an actual event has arrived; installed handlers alone are not labelled as live activity. Subagent start/stop events create separate child cards.

## Data and cost

Orbit stores only the link preference in macOS UserDefaults. Account email, plan and authentication-method labels remain in memory. It never reads provider credential files, copies authentication tokens, logs authentication output, or asks for a password. Account parsing retains only display fields. Provider tools retain responsibility for their own secure credential storage and browser callbacks.

No provider inference request is made by connecting an account, checking it, or receiving activity. Orbit has no account backend, hosted OAuth server, mandatory API key, or billable AI dependency. Users remain responsible for their provider’s normal plan limits and any usage they initiate in that provider. Account connection is not a promise of unlimited AI access.

OpenAI documents app-server authentication for local/open-source integrations and recommends its newer Sign in with ChatGPT system for broader integrations; the app-server route is not for commercial or hosted services. Orbit’s current free local design uses that documented local route. [OpenAI authentication guidance](https://learn.chatgpt.com/docs/app-server#authentication).

Anthropic distinguishes its own subscription clients from third-party model services. Orbit delegates sign-in to the official Claude Code tool and only observes account metadata and local lifecycle activity; it does not route its own model requests using a subscriber’s credentials. [Anthropic account guidance](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account).

## Limits and verification

- Each provider card represents the provider configuration used on this Mac, not a universal account-wide task feed. Separate profiles/configuration directories and other computers need their own connection.
- Local session files are a compatibility adapter, not a stable provider API. Schema changes can require an Orbit update. Hooks remain independent and require provider review; disabled or untrusted hooks cannot report approval requests.
- Local detection reads bounded recent JSONL records from the configured Codex `sessions` and Claude `projects` directories. Only session IDs, project basenames, models, lifecycle tags and timestamps are retained in memory. Prompt/reply/tool text is not decoded into retained objects, displayed or saved; credentials and conversation databases are not accessed.
- A local task with no lifecycle activity for fifteen minutes becomes stale; hook-only producers retain the five-minute limit. Stale does not mean completed. Orbit does not fabricate a percentage.
- Active sessions appear first. The compact notch rotates between agents, shows a live count for multiple sessions and briefly shows Done/Failed when a terminal event arrives. Each session has its own elapsed clock.
- The provider tools are optional. Missing tools show installation guidance; the rest of Orbit still works.
- Fresh browser authentication must be completed by the account owner. Development checks use existing sign-ins and synthetic protocol/event fixtures, without starting models or changing provider credentials.
