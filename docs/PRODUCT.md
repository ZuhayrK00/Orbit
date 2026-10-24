# Orbit product guidelines

## What it is

Orbit puts the small jobs you do throughout the day within one gesture of your cursor. Hold a chosen mouse button or press a recorded keyboard shortcut to open a wheel. Move to an action and release, or click it. The same toolkit is available through a configurable expanding notch panel and the menu bar.

It is a native Mac app, free for everyone, with no ads, subscription, signup or required internet connection. Source code is MIT licensed. Files and agent summaries stay on the user's Mac.

## Who it serves

People who regularly switch between text, files, notes, audio, timers and their apps. Agent status is an optional tool for people who run coding agents; it is not required to get value from Orbit.

## The daily experience

1. Open Orbit for a three-step introduction, surface choices, and optional permission setup. No account or mandatory permission gate. Try the wheel directly or preview the notch. The initial wheel has Files, Clipboard, Sound, Now Playing, Timer, Calendar, Agents and Settings.
2. Choose the actions you use. Add an app, link or Apple Shortcut; edit labels and order. Keep 4–12 items so the wheel remains quick to scan.
3. Choose your gesture: keyboard toggle or hold, or a mouse button with a deliberate hold delay. Grant global mouse access only if you want that gesture.
4. Enable whichever surfaces suit you. The notch opens inside the visible island’s horizontal bounds, including the exact top screen edge. Other parts of the menu bar never activate it. Width, clipboard-history height limit, hover delay and collapse delay are adjustable. Other tools size themselves to their content. A display without a notch gets a top-edge pill. The menu bar opens those controls inside its popover. Choosing a wheel utility transforms that same panel into a tool, with a button to return to the wheel. The main window is for settings and connections only.
5. Choose files explicitly, then convert, compress, ZIP or create renamed copies. Originals remain intact. Enable clipboard history, media controls, notification mirroring and agent connections separately.

## Design rules

- Make the frequent action easy to find and fast to reach.
- Give users a clear way to turn each surface and integration off.
- Show a real state: an agent is working, waiting, finished, failed or stale. Only show a progress bar when a producer supplies measured progress.
- Explain unsupported actions at the point of use. Hardware with fixed volume should not show a pretend working slider.
- Preserve original files and existing integration settings.
- Keep permission requests attached to the feature that needs them. A shared Permissions page and optional setup controls show live status, purpose, Settings links and guided recovery. Do not request unused Camera, Microphone or Full Disk Access grants. Never claim system-audio authorization from the screen-recording preflight.
- Confirm permission with live, persistent status. Show macOS permission and mouse-listener readiness separately; never imply access was granted just because Settings opened.
- Use compact matte-dark panels, restrained semantic colour, small rounded controls and readable native typography. Reserve material for transient feedback rather than nested controls. Align settings switches in a trailing column and keep navigation in a persistent sidebar. Respect system motion, contrast and transparency preferences.
- Give the notch independent width and height springs: height leads the opening, a small bounded overshoot settles naturally, and closing pulls up before narrowing without passing the compact size. Stage the page's top-centred scale and fade after the shell starts moving; floating shortcuts follow its sides. Preserve position and velocity through hover reversals and content-height measurements. Keep the background solid; Reduce Motion snaps directly to the final layout.
- Identify Codex and Claude consistently in connection cards, sessions, usage and live activity with their installed apps' menu-bar marks. Cache local artwork; use an installed app icon or distinct code/sparkle symbols when no template is available. Never download or bundle third-party artwork. Keep provider identity visible for waiting/completed activity with a small status badge, and respect reduced motion for the working pulse.
- Default to a plain-black notch without permanent branding or a close chevron. A dedicated Notch settings page provides a live layout preview, opaque dark tints and optional coloured outlines. Users can hide or reorder each shortcut and place it left, right or below; hiding all shortcuts leaves the title menu for navigation. Preserve full 44-point hit targets, help labels and accessibility names. Rail bounds follow the visible buttons; hidden rails have no hit targets, and turning all shortcut buttons off releases the extra canvas. Reserve bottom shortcut space before measuring the body so controls remain on screen. Measure the body at its configured width and fit it to the actual content, including disclosure changes, feedback and live data. The heading uses the physical camera’s wings instead of reserving a blank compact-height band. Keep both rails visible for short tools. The whole notch must not scroll: page long agent/device/app lists, and constrain only clipboard history and text-writing areas. The previous height preference now controls the clipboard viewport; regular tools are bounded by the available display above the Dock.
- Notification mirroring is optional and off for new installs. Read only new visible macOS banners through Accessibility; do not open Notification Center history, change native banners or bypass Focus. Provide automatic-expansion, preview and duration controls plus a clear permission state. Keep a bounded, paged inbox in memory; clear on disable, lock and quit. Previews off must redact existing content too. Real arrivals never steal keyboard focus or replace an open utility.
- Animate only the compact icon: a layered pulse for working agents, decorative moving bars for music, a 60-second sweeping timer hand, and one arrival bounce for copies, notifications and completions. The music bars are an activity cue, not measured audio levels. Paused timers stay static. The Notch → Behaviour animation switch and both app/system Reduce Motion disable all icon motion. Event IDs prevent store ticks from retriggering a bounce; expanded/disabled notches remove the animated view.
- Idle geometry matches the physical camera. Active geometry keeps that height and uses content-measured wings. Allow activity over menus by default, matching the reference default; no Accessibility grant is required for normal live indicators. Optional menu avoidance uses the bare cutout when space is unknown or crowded. No permanent activity footer is added. Read only front-app menu rectangles with existing Accessibility access and public status-window bounds, off-main, with bounded reads. Front-app/display changes invalidate the space measurement. Compact hover activation stays camera-width; the expanded tool stays available when compact indicators cannot fit. Notchless screens use a 220-point pill and no artificial camera spacer. Display changes recalculate the geometry; expanded width remains a separate preference, defaulting to 440 points for new configurations and bounded by the screen plus visible shortcut rails.
- Live compact activity stays clear of the camera: local agent elapsed time, countdown/paused timer, Music/Spotify track, or a short copied-item indicator. No copied text is exposed in the compact preview. Waiting agents take priority. Keep an explicitly chosen ongoing activity stable, falling back in timer/agents/music/keep-awake order. Hovering with several activities reveals a compact selector; allow explicit timer-plus-agents or timer-plus-music pairs while the timer runs. Pausing the timer shows its own mark again. Hold music paused from the chooser until the pointer leaves. Let users step through running agent clocks, keeping the chosen session stable. Timer completion interrupts for eight seconds, then returns to the selected activity; the finished state remains dismissible in the Timer tool. Clicking the camera area reopens the last explicitly selected tool; side indicators open their own activity. Keep this selection across relaunches; automatic notification popups are transient and never overwrite it. Selecting Notifications explicitly still remembers that tool.
- Show connected accounts in every agent surface even before a session emits an event. Connection is separate from activity; never invent a running task from sign-in alone. Elapsed time starts at an observed turn/start event, persists across callbacks, stops on completion and freezes when activity goes stale.
- Keep tools inside the notch, wheel or menu-bar popover. The main window contains settings, onboarding and connection management. External app/link/Shortcut actions still launch their explicitly chosen destinations.
- Keep the timer ring and use a borderless numeric duration with comfortable −/+ targets. Settings → Timers manages 1–8 ordered presets, each from 1 minute to 24 hours. Save stable identities and order locally; share the same choices across all three tool surfaces. Default to 5, 15, 25 and 45 minutes for existing and new installs. Preset edits must never restart or change a running countdown.
- Click-open pins the notch until outside click, Escape or Close notch in the title menu. Hover-open follows the configured delay and collapse behaviour. Floating controls are part of expanded retention only; idle activation remains confined to the compact width.
- Keep the configured utility wheel stable. An optional text wheel appears only when explicitly invoked with a readable text selection; a centre button returns to the user’s tools. Transform actions copy results, while replacement requires an explicit command and revalidation of the original selection.
- Use public macOS APIs and local processing. Avoid an always-on server or paid AI dependency.

## Implementation choices

SwiftUI renders the toolkit and settings. AppKit manages cursor panels, notch positioning and menu-bar access. Carbon registers keyboard shortcuts; Core Graphics monitors the chosen mouse button. ImageIO handles image processing, Core Audio handles sound, and Foundation handles settings and agent summaries. The repo has no third-party packages. Text transforms use Foundation, selected-text integration uses the public Accessibility API, and keep-awake sessions hold a temporary IOKit idle-sleep assertion. Scratchpad notes save atomically to a private local JSON library, preserving the former text file on migration. Clipboard I/O runs in a serial background actor; shelf file references use bookmarks and image assets use a private cache.

Music and Spotify expose the initial media integrations through Automation. Calendar uses EventKit for an opt-in read-only agenda and user-initiated meeting joins. Screen text uses region capture and local Vision OCR. File conversion currently means supported image formats, not arbitrary document, video or audio conversion.

## Release boundaries

This first version is a functioning development build. Before a public stable release, exercise mouse hold forwarding, signed-app permissions, sleep/restart timers, Music/Spotify controls, multiple displays and process-tap playback on real devices. Per-app audio mixing remains experimental until that matrix passes.

Codex and Claude Code accounts connect through their official local tools. Activity combines opt-in, bounded read-only local lifecycle metadata with optional explicit hooks for supported local sessions. Local metadata is kept in memory, with no prompt, reply or tool text retained. Account sign-in does not import every cloud or web chat. Additional providers need a documented account and event interface; Orbit must not depend on private conversation databases or login-token scraping. See ACCOUNT-CONNECTIONS.md for current scope.

## Later additions

Good additions fit the same model: a self-contained utility, a quick control, or an explicit local adapter. Examples include more native file transformations, more documented media sources and a public action-provider interface. They must preserve the free, local core and avoid mandatory backend costs.

See [costs](COSTS.md) and [validation](VALIDATION.md) for financial and release constraints.

## Reference-informed additions (7 October 2026)

- **Text Studio and text wheel:** selection actions inspired by PopClip, presented through Orbit’s existing radial surface and a source/result workspace. An optional miniature selection wheel is available; extension-package compatibility is not implemented.
- **Scratchpad:** multiple autosaved notes with Markdown previews and clickable checklists available from the same surfaces, with clipboard append and text-tool handoff.
- **Keep awake:** timed, end-time and indefinite sessions with an explicit stop control. Configurable display sleep, start on launch, power/display/app automation (Any/All), pointer intervals, pause on lock and battery cutoff. Manual stop suppresses automation until conditions clear. Closed-lid mode is an explicit per-session administrator-approved temporary override, capped at 12 hours, with heartbeat/parent/expiry/battery cleanup and a recovery marker for interrupted guards. No password or permanent privilege grant is stored.

Vorssaint’s modular utilities informed the feature priorities. These implementations use native frameworks and Orbit’s components; reference source and branding were not incorporated. Full-featured distribution is planned as a signed, notarized direct download. The App Store would require a separately validated sandboxed edition.

## Productivity expansion — 15 October 2026

The shelf, rich clipboard, download activities, agenda/meeting joins, OCR, named wheels/submenus, focus cycles/stopwatch, notes, optional Home, selected-text mini-wheel and agent-linked Keep Awake are implemented. Optional integrations stay off until chosen. Existing settings, notes and physical audio gains retain their meanings. See [feature guide and limits](PRODUCTIVITY.md) for controls, data handling and verification boundaries. No new service, model-inference call, package or recurring cost is introduced.
