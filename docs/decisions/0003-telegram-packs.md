# ADR 0003 — Telegram sticker-pack creation UX

**Status:** Accepted (spike #47). Implements as #48. Depends on the WebM (VP9 + alpha) encoder
from ADR 0002 / #42b for video stickers.

**Context.** Sticker Maker is a **paid, closed-source, privacy-first** (on-device, no servers, no
accounts, no data collection) Android-first Flutter app. It already builds and validates local packs
(#45) and renders assets to PNG / GIF, with WebP + WebM landing via the native encoders (#42b).

Telegram is deliberately different from WhatsApp: **there is no client-side, third-party pack-creation
API.** Packs are owned by a Telegram *user* and are created only through Telegram's own surfaces:

- **@Stickers bot** — the official, universal path. `/newpack` (static), `/newvideo` (video), then the
  user sends each asset, sets emoji, and `/publish`es. Returns an install link `t.me/addstickers/<name>`.
- **`t.me/addstickers/<name>` / `tg://addstickers?set=<name>`** deep links — **install an existing
  pack**; they cannot create one.
- **Bot API `createNewStickerSet` / `addStickerToSet`** — programmatic creation, but **only a bot can
  call it, from a server, for a known `user_id`**. Requires a backend + obtaining the user's Telegram
  id.
- **TDLib** — a full Telegram *client* library; using its sticker methods means embedding a client and
  making the user **log into Telegram inside our app**.

Hard constraints: **legally clean** (respect Telegram ToS, no automation that impersonates the user or
scrapes), and **keep our privacy promise** (no servers, no account, nothing leaves the device except
what the user explicitly shares).

## Decision

Ship a **guided @Stickers-bot flow** as the primary Telegram pack path, with **share-to-Telegram of
individual stickers** as the always-available fallback. No backend, no login, no automation of the
user's account — the user performs the creation in Telegram; we make every step as short as possible.

### The chosen flow (#48)

1. **Batch-export** the pack's assets on-device in Telegram-valid formats: static → 512² **PNG/WebP**;
   video → 512px **WebM VP9 + alpha, ≤ 3 s, ≤ 256 KB** (validated by `ComplianceValidator`, #49).
   Save them to a temp dir in pack order, named so they're easy to send in sequence.
2. **Copy the pack's emoji/name** to the clipboard and show a **step-by-step overlay** ("Send these 5
   files to @Stickers, then paste the emoji when asked…"). The overlay tracks progress and stays on top.
3. **Open @Stickers** pre-seeded with the right command via
   `tg://resolve?domain=stickers&text=%2Fnewvideo` (or `%2Fnewpack`) — the user taps send, then sends
   the exported files (via our share action) one by one following the overlay.
4. On `/publish`, the bot returns `t.me/addstickers/<name>`; we offer an **"Add to Telegram" install
   deep link** and store the pack's Telegram name so re-install/verify is one tap later.

This is 100% on-device and ToS-clean: Telegram creates and hosts the pack; we only export assets and
guide. The clipboard/`text=` prefill are conveniences, not account automation.

### Fallback ranking (best legally-clean in-app UX first)

| # | Option | Creates a pack? | Verdict | Why |
|---|--------|-----------------|---------|-----|
| **1** | **Guided @Stickers-bot flow** (export + overlay + `text=` prefill + install deep link) | Yes (user-driven) | **Primary** | Only universal, ToS-clean, no-backend way to actually create a pack. Multi-step, but we shorten every step. |
| **2** | **Share-to-Telegram of individual stickers** (system share sheet → chat) | No (single stickers) | **Fallback** | Zero-friction, works today, no @Stickers detour. For users who just want to send one, not build a pack. |
| **3** | **Install deep link** `t.me/addstickers/<name>` | No (install only) | **Sub-step of #1** | The final install/verify tap after creation; also re-share to friends. Not a creation path on its own. |
| **4** | **Bot API `createNewStickerSet` backend** | Yes (programmatic) | **Rejected (v1)** | Needs our server + the user's Telegram `user_id`; breaks the no-servers/no-data promise. Revisit only as an *opt-in* cloud feature. |
| **5** | **TDLib `importStickers` / client embed** | Yes | **Rejected** | Requires the user to log into Telegram inside our app; heavy client, session/2FA handling, privacy and ToS risk. |
| ~ | **Clipboard/UI *automation* of @Stickers** (auto-typing, auto-sending on the user's behalf) | — | **Rejected** | Automating a user's Telegram account is against ToS and fragile. We prefill/guide only; the user always taps send. |

### Why not the "obvious" shortcuts

- **"Just deep-link to create a pack."** No such deep link exists — `addstickers` only *installs*. There
  is no `tg://` verb that opens a create-pack UI pre-filled with our assets.
- **"Run a bot to do it automatically."** `createNewStickerSet` is a *bot*, server-side call needing the
  user's `user_id`; standing up that backend and collecting an id contradicts the app's core privacy
  promise and adds infra we deliberately don't have. Parked as a possible future opt-in.
- **"Embed TDLib."** Making users sign into Telegram inside a sticker maker is a large trust/UX/ToS cost
  for a feature the @Stickers flow already delivers on-device.

## Consequences

- #48 implements flow steps 1–4: a `TelegramPackExporter` (assets + ordering), an overlay/coach UI, the
  `tg://resolve?...&text=` open, our existing share action for sending files, and an install-deep-link
  action. State (Telegram pack name) persists on the `StickerPack`.
- **Blocked on #42b** for video stickers (WebM VP9 + alpha). Static-only Telegram packs (PNG/WebP) can
  ship first; video packs follow the encoder.
- **Device/human verification required** (not autonomously testable): the actual @Stickers hand-off,
  `text=` prefill behavior, and install deep link must be validated on a real device with the Telegram
  app installed — the #48 acceptance test ("a 5-sticker pack, static + video, created and installed via
  in-app guidance only").
- **Host-testable now:** asset export/ordering/format validation, the deep-link URL builder
  (`tg://resolve?domain=stickers&text=…` and `t.me/addstickers/<name>`), and the overlay step model —
  these get unit/widget tests in #48.
- Compliance: no new licenses; reuse the OSS-licenses screen (#53). No data leaves the device.

## References

- Telegram, *Stickers* — https://core.telegram.org/stickers (formats: video WEBM, 512px, ≤ 3 s, ≤ 256 KB)
- Telegram, *Deep links* — https://core.telegram.org/api/links
- @Stickers bot commands: `/newpack`, `/newvideo`, `/addsticker`, `/publish`; share link
  `t.me/addstickers/<name>` (verified July 2026).
