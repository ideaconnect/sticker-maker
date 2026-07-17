# Sticker Maker

*Make it stick.*

A mobile app (Android first, iOS second) for turning your own photos into stickers for Telegram,
WhatsApp and other messengers — with fully **on-device AI background removal**, playful text and
comic-bubble decoration, and animated-sticker (GIF / animated WebP / WebM) creation.

Paste a photo of your dog from the park, tap **Cut out**, add a big *"WOOF!"* caption, and send it
to your friends. Add frames and you've got an animated sticker.

## Status

**Planning phase.** The build is driven by GitHub issues generated from
[`docs/GITHUB_ISSUES_PLAN.md`](docs/GITHUB_ISSUES_PLAN.md) — the complete product plan, locked
technical decisions, milestone/issue breakdown (M0–M8), and the procedure for generating the
issue tracker.

## Key decisions

- **Framework:** Flutter (Android primary target; iOS from the same codebase in a later milestone).
- **AI background removal:** hybrid, all on-device — ML Kit Subject Segmentation on Android,
  Apple Vision on iOS, bundled Apache-2.0 open-source model as fallback. No cloud, no uploads.
- **Integrations:** share-sheet export first; native WhatsApp sticker-pack and Telegram pack flows
  in a dedicated milestone.
- **Business model:** paid app, minimal one-time price, fully featured — no ads, no freemium, no IAP.

## Design

The approved UI design lives in [`design/`](design/) as an interactive Claude Design mockup —
open [`design/Sticker Maker.dc.html`](design/Sticker%20Maker.dc.html) in a browser. It defines the
three screens (Home, Editor with six tools, Export) and the dark visual language used throughout.
