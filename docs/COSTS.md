# Orbit costs

Checked 7 October 2026. These are incremental service costs for this implementation, using the Mac, Xcode and Apple Developer membership you already have. Development time, electricity, your existing subscriptions and membership renewal are outside that total.

| Item | Build / launch cost | Recurring Orbit charge | Decision |
| --- | ---: | ---: | --- |
| Swift, SwiftUI, AppKit and macOS frameworks | £0 | £0 | Existing development tools and operating system. |
| Image processing and ZIP tools | £0 | £0 | ImageIO and built-in `ditto`; no conversion API. |
| Settings, timer and clipboard storage | £0 | £0 | Local files and memory; no cloud database. |
| Sound, notch and menu-bar controls | £0 | £0 | Native public APIs; no purchased driver. |
| Orbit LLM usage | £0 | £0 | No LLM is called by Orbit. |
| Hosting / domain / server | £0 | £0 | None needed for the app. A custom website is optional. |
| Signing and notarization | £0 additional | £0 additional | Included in your existing Developer membership. Its normal renewal still applies. |
| Local builds and tests | £0 | £0 | Run them on the existing Mac. |
| Public GitHub standard-runner CI | £0 | £0 | Public standard runner minutes are free; this workflow uploads no artifacts or caches. |
| App price | £0 | £0 | Free for users; no ads, trials, paid tiers or billing integration. |
| **Required incremental total** | **£0** | **£0 / month** | No purchase is needed to use this development build. |

Apple lists Developer ID and Mac notarization among [Developer Program membership benefits](https://developer.apple.com/support/compare-memberships/). A public release still needs Developer ID signing and submission to Apple's notary service; local builds can use your installed Apple Development certificate, with ad-hoc signing as a fallback. That is a release task, not a new paid service requirement. [Apple's distribution process](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

[GitHub's billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions) says standard hosted runners are free in public repositories. Private repositories have included allowances and can be billed beyond them; larger runners are charged separately. Orbit's workflow skips private repositories. Use local scripts while the repo is private, or make a deliberate CI choice later. Nothing has been published from this workspace.

## Connected agent costs

Reading a small status event costs Orbit nothing. Connecting Claude Code or Codex does not make a model call. Starting an agent task through an existing provider still uses that provider's own authentication, usage limits and billing. Orbit cannot make a paid provider free; its adapters add no API key, model request or automatic background run.

## What might cost money later

A custom domain, paid hosting, sponsored distribution infrastructure or additional AI features would be separate product decisions. None is required by this version. Normal bandwidth, GitHub usage and Apple's terms remain subject to their platform limits; the app's architecture does not incur a bill as more people run it locally.

For a zero-cost launch path: build locally, use the existing Developer ID membership to sign and notarize, and distribute a free app with the public source repository. Users download once and run tools on their own Mac.

## Account linking

Codex and Claude Code account checks use their installed official tools and make no model calls. Browser sign-in is managed by those tools. Orbit needs no hosted account server, purchased OAuth service or API key for subscription sign-ins. Optional activity hooks also run locally. Users’ own provider plans and any usage they initiate remain their responsibility; linking an account does not provide unlimited or free AI inference. See [account connections](ACCOUNT-CONNECTIONS.md) for the supported routes and boundaries.

## Text, scratchpad and keep awake

These additions use Foundation, Accessibility, local UTF-8 storage and IOKit. Incremental backend, model and service cost: **£0**. Search web opens DuckDuckGo only when chosen; it does not use a paid search API. The planned direct download can use a public GitHub Release asset, without a purchased domain or separate download server. Apple Developer membership renewal remains the existing recurring requirement for signed public releases.

## Agent usage readings

Codex quota reads and the Claude status-line metrics connector make no inference requests. The bridge, diagnostics and child-agent cards add **£0** in Orbit service costs. A provider-reported API-value estimate is labelled as such and is not treated as an amount charged to a subscription user. Existing provider plans and their usage remain separate.
