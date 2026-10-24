# Orbit

**Your Mac, within reach.** A free, local macOS toolkit with a configurable cursor wheel, expanding notch and menu-bar controls.

No Orbit subscriptions, advertising, analytics, Orbit accounts or model API calls. MIT licensed. Your existing Apple Developer membership can sign public releases; no hosting is needed to run the app.

Read the [product guidelines](docs/PRODUCT.md), [new productivity tools](docs/PRODUCTIVITY.md), [cost breakdown](docs/COSTS.md), and [validation report](docs/VALIDATION.md).

## Run

Runs on macOS 14 or later; building requires Xcode 26 or later. Per-app mixing requires macOS 14.4 or later. There are no package downloads or external runtime dependencies.

```sh
./scripts/run.sh
```

This builds `build/Orbit.app`, signs it locally, and opens it. To build a release:

```sh
./scripts/build-app.sh release
open build/Orbit.app
```

Open `Orbit.xcodeproj` in Xcode, select the Orbit scheme and My Mac, and choose your signing team to build and run a native app bundle. The app links the local OrbitCore package. `Package.swift` also supports source editing and command-line tests. Launch a bundled app: notification, Automation and system-audio permissions belong to the app bundle, not an unbundled `swift run` executable.

The packaging script signs and verifies a fresh bundle before replacing the previous build, preserving its signing identity when a single Apple Development identity is available. Use the same team in Xcode: an ad-hoc or differently signed build can require another permission grant. **Settings → Permissions** is the shared access dashboard. Accessibility is also shown beside the features that use it and during setup. If macOS still reports no access, **Already enabled?** identifies the running copy and offers a scoped recovery flow. Orbit only shows **Allowed** when macOS confirms access.

## Getting around

First launch has three short setup screens: welcome, access surfaces, and optional permissions. Setup can be skipped and reopened using **Quick setup**. Existing wheel actions and settings are preserved.

- **Keyboard:** Control–Option–Space toggles the wheel initially. Record any combination containing Control, Option or Command in **Settings → Controls**. Choose toggle or hold-and-release.
- **Mouse:** hold mouse button 4 (the first side button) for 0.18 seconds. Move toward an action and release. Change the button, delay and behaviour in settings. A short click is forwarded normally when Orbit reserves the held button.
- **Notch:** hover within the visible island’s width, including the very top pixel of the screen. The panel expands after the configured delay; the rest of the top edge does not activate it. On displays without a notch, it works as a top-edge pill. Disable hover to use a click instead. Idle stays plain black, with an optional outline. The expanded surface and its floating buttons share your glass colour and transparency. Running timers, local agent elapsed time, music and a brief copied-item indicator appear in small, measured spaces beside the camera without needing Accessibility access. Multiple agents show a count and a stable elapsed clock; choose another session in the activity chooser. Completion briefly shows Done or Failed. With several activities running, hover to choose one; the choice stays selected. A running timer can explicitly pair with agents or music. Approval requests take priority, and brief notices return to the chosen activity. Floating icon buttons switch tools inside the expanded notch. Click the camera area to reopen your last selected tool; click a side indicator to open that activity. With one ongoing activity, hover opens your remembered tool; with several, it reveals the compact chooser. Right-click the camera area also offers the chooser when hover is off. Clicking keeps the panel open until you click away, press Escape or choose Close notch from the title menu. Your last tool is remembered after restarting Orbit too; automatic notification popups do not replace it. Hover-open still uses your configured close delay.
- **Menu bar:** click Orbit’s hexagonal icon and choose a tool. Its controls open inside the popover. The Orbit app menu also offers **Open Orbit controls**.
- **Wheel:** choose a utility to turn the wheel into its controls. Set a custom timer, manage files or check agents right there. The circle morphs into a rounded, content-sized panel with Back, Pin and Close controls. Back returns to the radial actions; there is no bottom toolbar. Releasing a held trigger keeps the chosen tool open. File Tools stays open while you select files in Finder; pin another tool to keep it open when clicking elsewhere.
- **Settings:** the main window contains configuration, permissions and account connections only. Reopen Orbit in Finder to recover settings if all triggers are disabled.
- **Escape:** return from a wheel tool to the circle, then close it. Turn off this two-step behaviour in Wheel settings. Escape also closes the notch.

Create Work, Media and Files profiles in **Settings → Wheel**, assign each its own shortcut, and add **Wheel submenu** actions to link profiles. The centre menu switches profiles. Existing default-wheel actions stay intact.

The wheel can contain 4–12 actions. Change their labels and order, or add an installed app, a web link or an Apple Shortcut. **Settings → Wheel** also controls pointer/screen-centred placement, wheel size, tool width, opacity, labels, animations and dismissal. Tool height follows content, with scrolling only once its height limit is reached. The idle notch matches the physical camera cutout. Compact activity stays at camera height and adds only the width its icon and reading need. Allow activity over menu items is on by default, so live indicators work without Accessibility. Turn it off to give menu items priority: this optional mode measures geometry with existing Accessibility permission and hides wings when space is unknown or crowded. Hover activation starts within the camera width; the chooser keeps its full area interactive. Notchless displays derive their collapsed size from the menu-bar height. Expanded width defaults to 480 points; saved custom widths are preserved. Expanded width, hover and collapse delays are adjustable. The notch measures each tool and grows or shrinks as controls change, without scrolling the whole popup. Agent collections use pages; app volumes and clipboard history have their own scroll areas with hidden indicators. Text editors scroll within their writing area. Scrollbar indicators stay hidden across Orbit, including Settings. Four accent colours, wheel size, opacity and reduced animation are configurable. Settings can be imported and exported.

Open **Settings → Notch** for a dedicated preview and three groups of controls:

- **Look:** enable/disable, six shared glass colour presets or a custom tint, shared transparency, optional outline colour/thickness, width and clipboard height limit. The notch outline also applies to its floating shortcut buttons.
- **Layout:** arrange floating buttons directly on the notch preview. Drag between left/right/below or reorder in place; click a button to rename it, change its action, move it with keyboard-accessible controls or remove it. The + buttons open a searchable tool picker, including Home, Shelf, Downloads, Calendar and screen OCR. Each side supports six buttons; below supports two rows of six. A corner grip or width slider resizes the expanded notch while height remains content-driven. Show/hide preserves your layout; Reset layout leaves appearance and visibility preferences intact. The optional notification inbox and title menu remain available independently.
- **Behaviour:** hover/collapse timing, preferred display, and independent compact indicators for agents, timers, music, keep-awake sessions, copied items and notifications, plus optional menu avoidance. Optional animated icons give working agents a soft pulse, music moving bars, running timers a sweeping hand, and new copies/alerts a brief bounce. Paused timers stay still; Reduce Motion overrides icon animation. Notification auto-expansion remains in Settings → Notifications.

Changes save automatically. Hiding a notch shortcut or indicator does not disable the underlying tool or change the wheel/menu-bar layout. Glass colour and transparency are shared with Appearance and apply across Orbit, including the floating buttons. The collapsed camera area stays black.

The interface uses compact dark panels, restrained colour, native switches, small rounded controls and coordinated transitions. Settings use a persistent sidebar; utility views share the same controls across the wheel, notch and menu bar. The notch defaults to solid black; colour, outline and floating shortcut placement are independent preferences. System Reduce Motion and Reduce Transparency settings are respected.

### App volume mixer

Open **Sound & mixer** from the wheel, notch or menu bar. Drag a horizontal slider, click a percentage to type a value, or mute an app; its previous level returns on unmute. Levels above 100% turn amber. App sliders use a perceptual curve for finer quiet-level control; existing saved physical gains and mute-restore levels are unchanged. Click an app icon to pin, reorder, pick its output or reset it. Apps sit in one compact scrolling list, with output and microphone controls fixed above it. Scrollbars stay hidden. **Settings → Sound** and the mixer options button share the same preferences. A missing saved output falls back to the current system output and reconnects when available. Quitting Orbit restores native playback; saved adjustments return when Orbit reopens.

### A wheel that responds to selected text

With Accessibility enabled, highlight text in a supported app and invoke the wheel. Orbit reads that selection once, on request. The text wheel offers Copy, case changes, Trim, Clean link (for web URLs) or Unique lines, Search web, and Text Studio. Text transforms copy their result; **Your tools** returns to the custom utility wheel. Turn this behaviour off in **Settings → Controls → Text actions in the wheel**.

Text Studio accepts manual input or the clipboard without Accessibility. It previews every transformation. **Replace selection** appears only for a captured selection with a range, and refuses replacement if the target, selected text or range changed. Unsupported applications can use Copy result instead. Secure text fields are excluded. Source text is held in memory; only choosing to add it to Scratchpad persists it. Search web sends source text to DuckDuckGo when explicitly clicked; local transforms do not use AI or a network service. PopClip extension packages are not supported.

The optional **Settings → Productivity → Actions beside selected text** mini-wheel appears after dragging or double-clicking a selection. It offers copy, case changes, link cleanup, web search and save to note. Exclude apps by bundle ID; secure fields are excluded. It is off by default.

### Keep Awake

The notch, wheel and menu bar share the same session. Choose a duration, an end time or ∞, then start. Display sleep is allowed by default. **Automation** can follow mains power, an external display or selected running apps; choose Any or All. A manual Stop suppresses automatic restart until the matching conditions clear. Automation and start-on-launch are off by default. Sessions stop at the configured battery limit (15% initially).

**Until agents finish** holds a separate idle-sleep assertion for current and newly observed active agents. Only explicit completion/failure events release their entries; silence or a disappearing session does not count as finished. Stop manually if telemetry is lost. The session respects the battery cutoff and has a 12-hour safety limit; it does not enable closed-lid mode.

Pointer movement is optional and requires Accessibility. It nudges one pixel and returns only if the pointer has not moved in the meantime; it skips recent movement, held buttons, screen edges and the lock screen. Choose a 15-second to 5-minute interval. Closed-lid mode is enabled separately during a running session and asks macOS for administrator approval **each session**. It lasts at most 12 hours, uses a short-lived heartbeat guard, and restores the previous normal-sleep policy on stop, expiry, battery cutoff or Orbit exit. No password, sudoers permission or launch daemon is installed. After a power loss or a force-killed guard, **Restore normal sleep…** offers recovery with administrator approval. Physical lid-close and privileged recovery still need device validation before public release.

Compact activity uses larger, colour-matched readouts aligned to the curved ends. Keep Awake reads “30m”, “1h30” or “∞”; the timer shows whole minutes until its last minute, then seconds. Physical camera space stays clear. On a display without a camera, the active island fits its contents without an artificial middle gap; idle keeps the existing plain black pill. Right-click anywhere on the strip to switch live activities.

### Logitech MX Master gesture buttons

**Settings → Productivity → Logitech gesture button** can recognise the default Control–Option–Tab chord or record a custom one. This is opt-in; Orbit reports shortcut conflicts and cannot distinguish the same keys typed on a keyboard. The MX Master 4’s physical event delivery still needs a hardware check.

If Logi Options+ owns the gesture button, Orbit's raw mouse recorder may never receive a numbered mouse event for it. Use its keyboard-shortcut assignment:

1. In Orbit **Settings → Controls**, enable **Keyboard shortcut** and choose **Press to toggle**. Disable the raw mouse trigger if you only want the Logitech mapping.
2. In Logi Options+, select the connected MX Master → **Global settings** → the button currently labelled **Gestures** → **Custom** → **Click** → **Keyboard shortcut**.
3. Press Orbit's shortcut on your physical keyboard in Logitech's recorder. Initially this is Control–Option–Space. The recorder may ignore automated keystrokes.
4. Click the gesture button to open Orbit, then click a wheel action. A second gesture-button click closes the wheel. Existing directional gestures stay assigned.

Shortcut injection may send a full key press/release immediately, so this mapping is for toggle behaviour, not guaranteed physical hold-and-release. App-specific Logitech profiles can override a global assignment. The MX Master 4's Haptic Sense Panel / Actions Ring control is a separate button; select that control instead if that is the button you want to replace. [Logitech's MX Master 4 guide](https://support.logi.com/hc/en-gb/articles/28321445268247-Getting-Started-MX-Master-4).

## Working features

| Tool | Behaviour |
| --- | --- |
| Text Studio | On-demand selected text or explicit clipboard input; case changes, trimming, single-line text, unique/sorted lines, tracking-link cleanup, URL encoding/decoding and JSON formatting. Preview, copy, or replace an unchanged supported selection. |
| Scratchpad | Multiple autosaved notes, Markdown preview, clickable checklists, copy and export. The original single note migrates without deleting its source file. |
| Keep awake | Timed, until-a-time or indefinite sessions; display-sleep control; optional start on launch; power/display/app automation with Any/All rules; optional small pointer movement; pause on lock and a battery cutoff. Optional closed-lid sessions use administrator approval and a temporary restoration guard. |
| Images | Convert to JPEG, PNG, HEIC or TIFF; set lossy quality and optional maximum dimension. Compression creates JPEG copies. JPEG flattens transparency onto white. Metadata is removed. Animated and multi-page sources are rejected. |
| Files | ZIP chosen files; create batch-renamed copies. Output names avoid collisions. Source files stay unchanged. |
| File shelf | Persistent files, links and images; drop onto the notch, drag out, pin, Quick Look, share, reveal, or hand files to conversion tools. File references use local bookmarks; imported image data is owned by the shelf. |
| Clipboard | Opt-in text/link/image/file history with search, pins, previews and keyboard navigation. Reads run off the UI thread. Session-only by default; retaining history across launches is a separate option, with app exclusions. |
| Downloads | Opt-in folder monitoring, byte counts and progress when the browser publishes a total, plus completed-file Open/Finder actions. Handles Safari packages and common partial-file suffixes. |
| Sound | Output and microphone faders, device selection, sound-effects output, and hardware volume/mute where supported. Fixed-volume devices are labelled. |
| App mixer | Direct per-app volume, mute/restore, 0–200% boost with limiting, saved output routes, pinned/reordered apps and a compact scrolling list of horizontal sliders. Click an app icon for routing/options or its percentage for exact input. Float32 stereo, mono and planar outputs; unsupported routes show an error and release native playback. No virtual driver or recording. |
| Now playing | Music and Spotify track title, artist, position, transport and their own volume controls. Opt-in Automation. Browser players are not integrated. |
| Notifications | Opt-in mirroring of new visible Mac banners using Accessibility. Configurable automatic expansion, previews and display time; temporary paged inbox shared with the wheel/menu bar. |
| Timer & focus | Countdown presets, configurable Pomodoro focus/break cycles and rounds, and a stopwatch with laps. Shared controls and compact live activity; state persists locally. |
| Calendar | Read-only agenda for the next seven days, calendar selection, an upcoming meeting countdown and explicit Join for recognised meeting links. Requires Calendar access. |
| Copy screen text | Select a screen region, recognise text locally with Vision, and copy it. Captures are deleted after recognition. Requires Screen Recording access. |
| Home | Optional stable overview of agents, music, calendar, shelf, timer and downloads. The Home-on-open option preserves the previously remembered tool. |
| Agents | Connect Codex / Claude Code accounts and view their account and plan. Detect local running sessions, independent elapsed clocks and completion; optional hooks add approval status. Older CLI/project adapters remain available. No invented completion percentages. |

Customize durations in **Settings → Timers**. Edit, add, remove or reorder presets from 1 minute to 24 hours; changes save automatically. **Restore defaults** brings back 5, 15, 25 and 45 minutes. Changing presets does not alter an active countdown.

## Permissions

The keyboard shortcut, notch and menu bar work without global mouse access. **Settings → Permissions** shows live statuses, what each permission enables, request buttons where appropriate, and direct System Settings links. Setup shares these controls and can be skipped. Status refreshes on app activation and while a permission page or guide is visible; refreshing never requests access. Automation preflights run off the main thread and do not launch target apps.

- **Accessibility:** mouse controls, selected text, optional notification mirroring and pointer movement. Status is separate from mouse-listener readiness. Input Monitoring has its own optional troubleshooting row.
- **Automation:** Finder selection, Apple Music and Spotify controls. Each running app has its own checked status; an app that is not running is marked as checked when used. File pickers and drops do not need Finder Automation.
- **Orbit alerts:** timer and focus completion notifications. Starting a timer asks only if undecided; a previous refusal does not reopen Settings. Mirrored Mac notifications use Accessibility instead. Banner delivery settings are reported separately from authorization.
- **Calendar:** full access is needed to read an agenda; write-only is not treated as allowed. Denied/restricted access leads to Settings. Revocation clears cached events and calendar choices. Orbit never creates or edits events.
- **Screen recording:** requested for screen-region OCR; text recognition and temporary image cleanup stay local.
- **Files & folders:** location-specific access is requested by macOS when you choose files or enable download monitoring. No broad Full Disk Access request is added.
- **System audio:** requested when an app volume/output adjustment first needs a mixer route. macOS does not offer a separate public authorization preflight; the page does not infer audio access from screen-recording access. Device volume does not require capture.

A floating guide accompanies Accessibility and screen-recording setup without taking focus away from System Settings; onboarding uses an inline guide. It confirms a grant automatically and offers help if the switch appears on but this build still has no access. **Start over…** asks for confirmation before resetting only Orbit’s selected Accessibility or Screen Capture grant, using the current bundle identifier. It never resets other permissions or apps. **Show this app** identifies the exact bundle; **Reopen Orbit** is available for screen-capture changes that need a new process.

A locally signed development build is not a notarized public release. The build script uses the sole installed Apple Development identity when available, so the signing identity remains stable across rebuilds. With no identity or multiple development identities, it falls back to ad-hoc signing; set `ORBIT_SIGNING_IDENTITY` to choose explicitly (or `-` to force ad-hoc). Switching from an older ad-hoc build can require allowing the newly signed copy once. The same override accepts a Developer ID identity for distribution. No identity or credentials are stored in this repository.

## Liquid Glass

Orbit uses Apple's native Liquid Glass on macOS 26 and later, with a material fallback on older systems. **Settings → Appearance → Glass colour / Glass transparency** controls every glass surface and button, including the shortcuts outside the notch, Settings, the wheel and menu bar. The same controls are available in Notch → Look. Colour changes update already-open surfaces; transparency adjusts the backing continuously without fading text or icons. Existing notch colours become the initial shared glass colour. Selection highlights keep their separate accent. macOS Reduce Transparency uses an opaque tinted backing. The camera area and collapsed notch stay black; the expanded surface fades into glass below it. Notch shortcuts are separate circular glass buttons and follow its optional outline colour and thickness. The notch keeps its active glass treatment when it gains or loses keyboard focus; its background is not an interactive control, and unchanged tint values are not reapplied during layout.

Now Playing loads cover art from Music's local artwork or Spotify's artwork CDN, keeps it in memory and removes Music's temporary extraction file. It uses the existing player connection; it adds no subscription or service charge. Missing artwork uses a music glyph. The compact music activity shares the same cover.

## Mac notifications in the notch

Open **Settings → Notifications** and enable **Show Mac notifications in the notch**. If the status says **Needs Accessibility access**, use **Allow Accessibility**, enable this copy of Orbit in System Settings, and return. Orbit detects the grant automatically. macOS notification permission for Orbit's own timer alerts is separate.

Choose a focused automatic preview or a compact banner with the app icon/name and message beside the camera, turn message previews on/off, and set a 3–15 second display time. Hover or click a compact notification to read it. The focused preview fits the message and available quick actions without tool rails or an inbox/settings footer; its timer waits while the pointer is over it. On expiry or dismissal, the notch returns to its previous activity and remembers your last utility. A new notification does not replace a utility already open in the notch. The heading’s bell and the preview’s Inbox button open the paged inbox; Notifications can also be placed on the wheel and opened in the menu bar. **Preview in notch** uses a labelled Orbit sample with a working Open app button, and follows the expansion/privacy settings without sending a system notification.

Only new, visible macOS banners are eligible. Old Notification Center history and notifications hidden by Focus are not imported. The first snapshot after enabling, unlocking, or closing Notification Center is a baseline. Source banners and sounds remain unchanged. macOS has no supported system-wide replacement API for third-party notification managers; disabling native banners also removes Orbit’s source. Orbit does not offer a misleading “default notifications” switch. Up to 30 notices stay in memory and are cleared on disable, lock/session suspension or quit; nothing is uploaded or persisted. App identities resolve to installed app icons where available. Click a card or Open app to open its source. Reply, Show in Finder and Open appear when the visible native notification exposes those actions; Reply hands off to its native reply control. Action handles expire as banners disappear. Clearing/dismissing Orbit's inbox affects only Orbit. Turning previews off redacts titles and bodies already in that inbox as well as new arrivals.

The reader uses public Accessibility calls, but Notification Center's accessibility roles/layout are macOS-version dependent. Unsupported or ambiguous snapshots are skipped, so cross-app delivery must be checked on each supported macOS release. The implementation is independent; [Vorssaint's documented mirroring behaviour](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PRIVACY.md) informed the feature scope. No paid service or new runtime dependency is used.

**Show incoming calls** reads visible Phone/FaceTime call surfaces, including their system helper interfaces. A call is recognized only when both Answer and Decline are exposed. These buttons invoke those specific live controls after a click; Orbit does not automatically answer calls. This remains dependent on macOS accessibility exposure, app language, and the current call interface, and requires an incoming-call device check.

## Agent accounts and activity

Open **Settings → Connections** and choose **Connect account** for Codex or Claude Code. Orbit recognises an existing provider sign-in or opens the provider’s browser login, then displays the account and plan. No API key is needed for subscription sign-ins. Credentials stay with the provider’s own tool.

Turn on **Local session activity** to detect tasks from local session metadata, including sessions already running. Existing activity-enabled providers retain monitoring on upgrade. No prompts or replies are stored or sent. Optional **Enable activity** hooks add approval-request status after provider reload and, for Codex, review in `/hooks`. **Stop activity** disables monitoring and removes Orbit’s global entries, preserving other settings. **Unlink account** stops account checks without logging the provider out.

This connects supported local sessions, not all web chats or cloud jobs under an account. Orbit makes no model calls; your provider’s normal plan limits and charges still apply to work you initiate there. The advanced section retains project-only Claude hooks and the Codex JSON wrapper.

See [account connections](docs/ACCOUNT-CONNECTIONS.md) for sign-in behaviour, costs and limits, and [agent integration](docs/AGENTS-INTEGRATION.md) for event adapters and removal.

Codex plan windows and reset times appear on its account card and in the notch. Claude's optional **Connect metrics** preserves an existing status line while adding model, context, token counts and provider-reported limits. Orbit updates an already-installed bridge executable when the app changes without rewriting hook settings. **Repair activity** fills in incomplete hooks; child agents have separate status cards. See the [feature audit](docs/FEATURE-AUDIT.md) for implemented coverage and remaining gaps.

## Local data

`~/Library/Application Support/Orbit/` contains:

- `configuration.json`: settings and wheel actions;
- `timer.json`: the current timer deadline;
- `notes.json`: autosaved notes and selection, with owner-only permissions; old `scratchpad.txt` is preserved after migration;
- `Shelf/`: parked-item metadata, file bookmarks and owned image assets;
- `Clipboard/`: session image assets and, only if enabled, persistent history;
- `focus.json` and `stopwatch.json`: focus phase and stopwatch state;
- `agents/`: small status summaries from explicitly connected agents;
- `agent-metrics/`: bounded local session metrics, without prompts or transcripts;
- `connections/`: owner-only records used to restore a connected Claude status line;
- `bin/`: the locally generated agent bridge and optional Codex wrapper.

Account-link preferences are stored in macOS UserDefaults; account display metadata stays in memory. Clipboard text is session-only unless **Save history across restarts** is enabled. Image previews use a private local cache even in session-only mode; it is removed on normal quit. Persistent history and pins are local and unencrypted, protected by file permissions. Disable history to clear it. Orbit skips pasteboard entries marked concealed, transient or auto-generated and supports app exclusions; source apps do not reliably mark all secrets.

Custom link / app / Shortcut actions run only when selected. Their destination may itself use the internet or paid services; Orbit does not provide those services.

## Verify

```sh
swift test
./scripts/build-app.sh debug
build/Orbit.app/Contents/MacOS/Orbit --smoke-files
python3 scripts/test-agent-bridge.py
```

Core tests cover wheel hit-testing across 4–12 slots, inclusive top-edge notch activation and display bounds, settings migration and round trips, timer deadlines, agent event parsing, staleness, malformed files and traversal-safe names. File smoke tests generate their own fixtures and validate conversion, resizing, original preservation, collision handling, batch rollback, renamed copies and ZIP integrity.

Hardware permission checks, third-party media integrations, multi-display notch behaviour and process-tap audio are separate device tests. See [validation](docs/VALIDATION.md) for the results of this build.

## Design & implementation references

Orbit’s original interface draws on modular utilities such as [Vorssaint](https://github.com/vorssaint/vorssaint-utils) and the selection actions described in [PopClip’s guide](https://www.popclip.app/guide/actions). The reference review used Vorssaint revision `9d762890e7a92489ea602b1835ecd0221cbcaba5` (GPL-3.0-or-later). The features here are independent implementations; no reference source or artwork is included in Orbit. Orbit keeps its MIT licence and its own visual identity.

- [Apple screen safe areas](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple event taps](https://developer.apple.com/documentation/coregraphics/cgevent)
- [Apple Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [Codex JSON event streaming](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)

This is an initial development release. The concrete platform limitations above are part of its scope.

## Distribution

The full-featured build targets a direct download: a Developer ID-signed, Apple-notarized `.dmg` or `.zip` attached to a GitHub Release. Users download through their browser, drag Orbit to Applications, and complete optional onboarding. A custom website can link to the same asset; no paid domain or app backend is required. GitHub documents release assets [here](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases), and Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/).

The Mac App Store is a different distribution track. [App Review guideline 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) requires sandboxing; the current build is not sandboxed and uses cross-app Accessibility, external provider tools and user-level hooks. An App Store edition would need a separately tested entitlement/feature design and review; this is not an App Store-ready binary. The local Apple Development signature is also not the Developer ID signature required for the public direct-download route. Nothing has been uploaded, notarized or published yet.
