# Play Store listing — copy & asset plan

Companion to #52 (graphics) and #51 (Console setup). This is the **text and the
capture plan**; producing the actual images and uploading them is a human step
(needs a device/emulator and Play Console access). Character limits are Google
Play's.

---

## Title (≤ 30 chars)

**Primary:** `Sticker Maker: Cut & Send` (25)

Alternatives:
- `Sticker Maker — Pet Stickers` (28)
- `Sticker Maker: Photo Stickers` (29)

## Short description (≤ 80 chars)

`Turn photos into stickers — auto cut-out, text & GIFs. For WhatsApp & Telegram.` (79)

## Full description (≤ 4000 chars)

```
Make stickers from your own photos in seconds — then send them anywhere.

Sticker Maker turns a photo of your pet, your friends, or anything else into a
clean, ready-to-share sticker. Tap once to lift your subject off its background,
add chunky captions and comic bubbles, drop on emoji, animate it, and export to
WhatsApp, Telegram, or a transparent PNG or GIF.

One paid app. Every feature included. No ads, no watermarks, no subscriptions,
no upsells — ever.

WHAT YOU CAN MAKE
• One-tap background removal — your subject, cut out cleanly.
• A classic white die-cut outline around the cut-out, adjustable to any width.
• Bold sticker captions and comic speech bubbles in playful fonts.
• Emoji and props dropped straight onto the canvas.
• Animated stickers — turn a few frames into a looping GIF.
• Fine-tune with brightness, contrast, saturation, hue and opacity.

SEND IT ANYWHERE
• Share to WhatsApp and Telegram, or save a transparent PNG or GIF.
• Build and organise sticker packs, with per-sticker emoji tags.

PRIVATE BY DESIGN
• Everything happens on your device. Your photos are never uploaded.
• Background removal runs locally — no account, no sign-in, no tracking.
• No analytics, no advertising IDs. We collect nothing. (See our privacy policy.)

WHY IT'S PAID
Because you're the customer, not the product. You pay once and get the whole
app — no ads interrupting you and no "unlock this for $2.99" nag screens.

Make it stick.
```

(~1,180 chars — well under the 4,000 limit, leaving room to localise or extend.)

## Promo / "What's new" (v1.0.0)

`First release! Make stickers from your photos: one-tap cut-out, die-cut
outlines, captions, comic bubbles, emoji, animated GIFs, and sharing to WhatsApp
& Telegram. Paid, private, no ads.`

---

## Graphics checklist (#52 — human/device)

| Asset | Spec | Source | Status |
|-------|------|--------|--------|
| App icon | 512×512 PNG, 32-bit | `assets/branding/icon.png` (already in repo) | ✅ have source |
| Adaptive icon | fg + `#131019` bg | `assets/branding/icon_foreground.png` | ✅ wired in pubspec |
| Feature graphic | 1024×500 PNG/JPG | **to design** — logo + tagline "Make it stick." on the dark gradient | ⬜ human |
| Phone screenshots | ≥ 2 required, up to 8; 1080×1920 (9:16) | capture from the app (plan below) | ⬜ human |

**Feature graphic direction:** dark background (`#0C0A11`), the app's violet→pink
hero gradient, the logo mark, tagline "Make it stick.", and one hero sticker
(pet cut-out with a white die-cut outline).

## Screenshot capture plan (≥ 6, in this order)

Capture on a device/emulator in the dark theme. Suggested caption overlays:

1. **Home** — "Your stickers, one tap away." (brand header, New Sticker hero,
   Recent grid). *Ready now.*
2. **Cut out (before → after)** — "Remove the background in one tap." Show the
   cutout tool mid-result. *Ready now (needs a real photo import).*
3. **Die-cut outline** — "Add the classic sticker outline." Adjust slider on a
   cut-out. *Ready now (#62).*
4. **Text & bubbles** — "Caption it. Speak your mind." Text + comic bubble on a
   sticker. *Ready now.*
5. **Emoji & props** — "Decorate with emoji." Emoji picker + a placed emoji.
   *Ready now (#61).*
6. **Frames / animation** — "Bring it to life." Multi-frame timeline → GIF.
   *Ready now.*
7. **Export & share** — "Send to WhatsApp, Telegram, or save." Export screen
   with the target picker + size estimate. *Ready now (PNG/GIF).* 
8. **Sticker pack** — "Build a pack." Pack manager with the Ready/Draft state.
   *Manager ready (#45); native WhatsApp/Telegram pack export lands with #46/#48.*

> Screenshots 1–7 reflect shipping functionality. For #8, capture the pack
> **manager**; the one-tap "install to WhatsApp/Telegram" step depends on the
> native encoders (#42b) + platform integration (#46/#48), so don't imply
> in-store that packs install until those land.

## ASO keywords (metadata / research notes)

sticker maker, sticker creator, photo sticker, pet stickers, whatsapp stickers,
telegram stickers, background remover, cut out, gif maker, animated stickers,
comic bubble, meme sticker.

## Pre-submit consistency checklist

- [ ] Title/short/full description entered and within limits.
- [ ] Privacy policy URL (see `docs/legal/privacy-policy.md`) entered and live.
- [ ] Data-safety form matches `docs/legal/play-data-safety.md` (no data collected).
- [ ] Screenshots don't advertise pack-install before #46/#48 ship.
- [ ] "No ads / paid / no subscription" claims match the actual build.
