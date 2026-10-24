# Productivity tools — 15 October 2026

These additions run locally and reuse Orbit’s notch, wheel and menu-bar controls. Open a tool from the notch title menu or add it to a wheel. The main window remains for settings. No server, paid API, new dependency or Orbit subscription is required.

## Controls and setup

| Addition | Where to use it | Behaviour |
| --- | --- | --- |
| File shelf | File shelf tool; drop file/link URLs onto the notch | Park files, links or image data; search, pin, Quick Look, drag out, share, reveal or hand files to File tools. A drop opens and holds the shelf. Original files are not moved or deleted by shelf removal. |
| Rich clipboard | Clipboard; Settings → Productivity | Text, links, images and file references; search, pins, image/file previews, copy and Add to shelf. Focus the list and use arrows, Return to copy and Space for file/image preview. |
| Downloads | Downloads; Settings → Productivity → Watch downloads | Watch the selected folder for Safari packages and common `.crdownload`, `.part` and `.partial` transfers. Live activity shows real progress when available, otherwise received bytes. Completed items offer Open and Finder. |
| Agenda and meetings | Calendar; Settings → Productivity | Connect Calendar, select calendars and browse seven days of events. Recognised upcoming meetings gain a compact countdown and an explicit Join button. |
| Local screen OCR | Copy screen text | Select a screen region with the native capture cursor. Vision recognises text on this Mac, copies it, and removes the temporary image. Escape cancels capture. |
| Wheel profiles | Settings → Wheel | Add the Work, Media and Files starters or create up to 12 profiles. Each has 4–12 actions and an independent keyboard shortcut. A Wheel submenu action opens another profile; Back returns to its parent. The wheel’s centre menu switches profiles. |
| Focus and stopwatch | Timer → Pomodoro / Stopwatch | Configure focus, short/long breaks and rounds in Productivity settings. Pause, skip or end phases. Stopwatch has pause/resume, laps and reset, with compact live activity. |
| Multiple notes | Scratchpad | Create/select/rename notes, edit Markdown, preview it, click `- [ ]` tasks, copy and export. Existing single-note text migrates without removing the original file. |
| Optional Home | Home; Settings → Productivity → Notch Home | Stable cards for music, agents, agenda, shelf, timer and downloads. Home-on-open is optional and does not overwrite the previously remembered tool. |
| Agent-linked Keep Awake | Keep awake → Until agents finish | Prevent idle system sleep for observed running agents. Newly running agents join the session. Explicit completed/failed events release entries; silence or stale/missing telemetry does not. |
| Fresh Claude limits | Agents → Plan usage / Connections | For compatible signed-in Claude Code versions, a control-only request refreshes plan windows. Older/unsupported tools retain existing local status-line metrics. |
| Logitech chord | Settings → Productivity → Logitech gesture button | Opt-in Control–Option–Tab recognition and a custom chord recorder. Use Logi Options+ to assign a chord when its gesture layer consumes the physical button. |
| Selection mini-wheel | Settings → Productivity → Show selection actions | Optional six-action palette after a mouse selection: copy, upper/lowercase, trim/clean link, search and save to note. Secure fields and excluded apps are skipped. A plain click beside an old selection does not reopen it. |
| Mixer curve | Sound & mixer | More room for quiet adjustments below 100%. Saved settings continue storing actual gain, so existing loudness, boost and mute-restore values are preserved without rewriting them. |

## Local data and optional access

Clipboard capture is opt-in and reads/decode work run in a serial actor away from the UI thread. History is session-only by default; **Save history across restarts** is a separate opt-in. Image data needs a private local cache even during a session. Normal exit clears session-only assets. Concealed/transient/generated pasteboard types are excluded, with per-app bundle-ID exclusions. Recent unpinned history uses the existing 5–100 limit, with up to 200 total entries including pins. Persistence uses owner-only files, not encryption. Unreadable saved libraries are preserved rather than overwritten.

The shelf is persistent. File entries refer to originals using local bookmarks; they are not backups. Imported image data is stored in the shelf’s own cache, so clearing clipboard history cannot delete an image transferred to the shelf. Dragging a multi-file clipboard entry currently exports its first file; Copy retains all its file URLs. File-promise-only drags from apps are not yet supported; use an exported file or file picker for those sources.

Calendar access is requested on connection. Orbit reads events and does not edit calendars. OCR asks macOS for Screen Recording access when invoked. Download monitoring can prompt for access to its folder. The selected-text palette uses existing Accessibility permission. These grants were not automatically accepted during development checks.

Notes, shelf, persisted clipboard, focus and stopwatch state live in `~/Library/Application Support/Orbit/`. Agenda events, download activity, selection text and account quota display stay in memory. Web search and meeting joins open their destination only when selected. Existing provider subscriptions are still needed for work you initiate in those providers; Orbit does not start model inference to show limits or progress.

## Compatibility and verification limits

- Download monitoring is folder-based, not a browser extension. Transfers must leave a recognised partial file long enough to be observed; instant downloads between scans, custom browser destinations and unsupported temporary formats may be missed. Byte totals depend on browser-published Foundation file progress. Unknown totals stay indeterminate. Completion requires the partial to disappear, a matching final file identity/size and two stable scans. A cancelled partial is not treated as a completed download merely because an older same-name file exists.
- Join accepts recognised Zoom, Google Meet, Teams, Webex and Whereby meeting URLs in event URL/location/notes. Host and path validation rejects ordinary home/chat links and lookalike domains. Wrapped redirect links and other providers are not currently unwrapped; open the event in Calendar for those.
- Claude `get_usage` is gated to CLI 2.1.286 or later. It is a compatibility protocol with timeout, cancellation and fallback, not a stable public API guarantee. The process receives no prompt and disables tools, hooks, MCP and session persistence. Synthetic protocol tests do not establish live support for every account/version. The version installed during this check is 2.1.280, so its local-sample fallback remains active.
- The Logitech recorder recognises a keyboard chord, not a hardware device identity. A keyboard can send the same chord. Real MX Master 4 hold/release delivery and app-specific Options+ profiles still need a physical check; immediate key down/up mappings work best in toggle mode.
- Focus phases advance once when an overdue timer is observed, starting the next full phase rather than replaying missed phases. Stopwatch elapsed time uses timestamps and includes sleep. Agent-linked Keep Awake has a 12-hour safety limit, respects the battery cutoff, ends on Orbit exit and does not enable closed-lid mode. Stop manually when lifecycle telemetry cannot provide an explicit end event.
- OCR recognition passed a rendered-text fixture; screen-region permission/cancellation flow needs a user-granted Screen Recording check. Calendar fetching/Join needs real Calendar permission. Actual browser progress publication, hardware mouse delivery and selection actions across third-party apps remain device checks.

See [validation](VALIDATION.md) for the build/test results and native UI checks. This remains a development build; no public release was uploaded.
