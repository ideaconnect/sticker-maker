---
layout: page
title: Features
eyebrow: What Sticker Maker does
lead: Six tools, one 512 × 512 canvas, and a background remover that never sends your photo anywhere.
description: Every Sticker Maker tool in detail - one-tap on-device cut-out, die-cut outlines, erase and restore, layers, colour adjustments, captions and comic bubbles, frames, and export to PNG, WebP, GIF and WebM.
hero_art: |-
  <div class="phone" role="img" aria-label="The Sticker Maker editor: a transparent checkerboard canvas with the Removing background overlay running, the Cut out tool selected in the tool bar.">
    <div class="phone-screen">
      <span class="phone-notch"></span>
      <div class="phone-bar">
        <span class="phone-bar-btn">&#8249;</span>
        <div>
          <p class="phone-bar-title">Park dog</p>
          <p class="phone-bar-sub">512 &#215; 512 &middot; transparent</p>
        </div>
        <span class="phone-cta sm">Export</span>
      </div>
      <div class="phone-body">
        <div class="phone-canvas checker selected">
          <span class="phone-handle tl"></span>
          <span class="phone-handle tr"></span>
          <span class="phone-handle bl"></span>
          <span class="phone-handle br"></span>
          <div class="phone-overlay">
            <span class="spinner"></span>
            <span>Removing background&hellip;</span>
          </div>
        </div>
        <span class="toast">Nothing leaves your phone</span>
      </div>
      <div class="phone-panel">
        <p class="phone-panel-title">AI background removal</p>
        <p>Lift your subject off its background. Runs on your device.</p>
        <span class="phone-cta">Working&hellip;</span>
      </div>
      <div class="toolbar">
        <span class="tool tool-layers"><span class="tool-ico">&#128450;</span>Layers</span>
        <span class="tool tool-adjust"><span class="tool-ico">&#127899;</span>Adjust</span>
        <span class="tool tool-text"><span class="tool-ico">&#128172;</span>Text</span>
        <span class="tool tool-erase"><span class="tool-ico">&#129529;</span>Erase</span>
        <span class="tool tool-cutout is-active"><span class="tool-ico">&#9986;</span>Cut out</span>
        <span class="tool tool-frames"><span class="tool-ico">&#127902;</span>Frames</span>
      </div>
    </div>
  </div>
---

Sticker Maker is one screen: a square canvas with your sticker on it, and a bar
of six tools underneath. Start from your gallery, from the camera, by pasting a
photo from the clipboard, or from one of the built-in **templates**
(pre-composed layouts you drop a photo into). Then work through the tools in
whatever order the sticker needs.

Everything below happens on your phone. No account, no sign-in, no upload.

## Cut out

Tap **Remove background** and the app finds your subject (your dog, your friend,
the ice cream) and lifts it off everything behind it. The button walks through
*Remove background → Working… → Undo removal*, so it is one tap forward and one
tap back.

Then add the classic sticker look: a **white die-cut outline** traced around the
cut-out, as thin or as chunky as you like. The cut-out is a mask over the
original photo, which is never thrown away, so you can undo, redo, or paint part
of the background back at any point.

<div class="card tool-cutout reveal">
  <h3><span class="ico" aria-hidden="true">&#9986;</span>Cut out <span class="badge">On device</span></h3>
  <p><b>One action button</b> with three states (Remove background, Working…, Undo removal) over a full-canvas progress overlay.</p>
  <p><b>Die-cut outline</b> around the subject, adjustable from a hairline to a chunky white border, so the sticker reads as a cut-out on any chat background.</p>
  <p><b>Non-destructive.</b> The photo stays intact underneath. Removal is a single undo step.</p>
</div>

## Erase and restore

Erase is a brush: paint to take pixels away, switch to **Restore** and paint to
bring them back. Automatic cut-outs are good but not psychic, and fur, hair and
thin ears sometimes keep a halo.

<div class="card tool-erase reveal">
  <h3><span class="ico" aria-hidden="true">&#129529;</span>Erase controls</h3>
  <p><b>Erase / Restore</b> modes, so one brush both cleans up and repairs.</p>
  <p><b>Brush size 8-120 px</b> with a live preview circle, and a <b>Soft edges</b> toggle for a feathered edge instead of a hard one.</p>
  <p><b>One stroke, one undo step.</b> A slip of the thumb is one tap to fix.</p>
</div>

## Text and comic bubbles

Type a caption and pick a font. It lands on the canvas with a thick contrasting
outline, so it stays readable on any chat background: light theme, dark theme,
someone's holiday photo wallpaper. This is how a photo of a dog becomes a
sticker of a dog saying **"Woof!"**

Comic **speech bubbles** come as five preset shapes (speech, thought, a spiky
shout, a tail-less caption box, and a dashed-outline whisper). The ones with a
tail let you drag it to point at whoever's talking. Bubbles are drawn as vector
shapes, so they stay crisp when the sticker is rendered out. Emoji and props
drop onto the canvas as their own layers.

<div class="card tool-text reveal">
  <h3><span class="ico" aria-hidden="true">&#128172;</span>Text controls</h3>
  <p><b>Five bundled display fonts</b> (Bangers, Luckiest Guy, Pacifico, Fredoka and Rubik), shown as chips rendered in their own typeface, so you pick by looking.</p>
  <p><b>Size 16-72 px</b>, nine colour swatches, and an automatic contrasting stroke around every glyph.</p>
  <p><b>As many text layers as you want</b>, each one movable, scalable and rotatable like anything else on the canvas.</p>
</div>

## Layers

Every photo, caption, bubble and emoji is its own layer. The Layers panel is the
stack: thumbnail, name, type, an eye to hide it, and a handle to drag it up or
down the order. Tap a layer on the canvas to select it and you get a dashed
selection frame with corner handles. Drag to move, pinch to scale, twist to
rotate.

<div class="card tool-layers reveal">
  <h3><span class="ico" aria-hidden="true">&#128450;</span>Layer controls</h3>
  <p><b>Add, reorder, rename, hide, delete.</b> The canvas updates as you go.</p>
  <p><b>Direct manipulation.</b> Move, scale and rotate on the sticker itself, with hit-testing that respects what's already been rotated.</p>
  <p><b>Undo and redo</b> across everything: transforms, adjustments, text edits, brush strokes.</p>
</div>

## Adjust

Colour controls, per layer. Match a caption to the photo, dim a background
layer, or push a dull phone snap until it looks like a sticker.

<div class="card tool-adjust reveal">
  <h3><span class="ico" aria-hidden="true">&#127899;</span>Adjust controls</h3>
  <p><b>Brightness, Contrast, Saturation: 0-200 %.</b> <b>Hue: −180° to +180°.</b> <b>Opacity: 0-100 %.</b></p>
  <p><b>Live preview</b> on the real canvas, a one-tap <b>Reset</b>, and every change is undoable.</p>
  <p><b>What you see is what exports.</b> Adjustments are baked into the rendered sticker.</p>
</div>

## Frames and animation

Add a second frame and your sticker starts moving. Each frame keeps its own copy
of the layer state, and the Add button duplicates the frame you're on, so
nudging a caption two pixels per frame is tap, drag, tap, drag.

Press play to watch it loop on the canvas, set the speed, and export it as an
animated sticker.

<div class="card tool-frames reveal">
  <h3><span class="ico" aria-hidden="true">&#127902;</span>Frame controls</h3>
  <p><b>Thumbnail strip</b> of every frame with the active one highlighted, plus duplicate, reorder and delete.</p>
  <p><b>Speed presets from 1 to 24 fps</b> with a live readout, and play/pause preview on the canvas.</p>
  <p><b>Per-frame editing.</b> An edit lands on the frame you're looking at, and a counter tells you which one that is.</p>
</div>

## Export and formats

The canvas is **512 × 512 and transparent**, which is the size messengers want.
The export screen shows a live preview over the transparency checkerboard, a
**Static / Animated** switch, a target picker, and the estimated file size
before you commit.

| Format | Good for | Notes |
|---|---|---|
| **PNG** | Transparent stills, saving to your gallery | Always 1024 × 1024, twice the canvas size |
| **WebP** | WhatsApp-style stickers, small files | Static and animated |
| **GIF** | Animated stickers that work everywhere | Loops, transparent, 256 colours |
| **WebM** | Telegram video stickers | VP9, short and silent, as Telegram requires |

From there, send it through the Android share sheet into a **WhatsApp** or
**Telegram** chat, or any other app that takes an image. Or save it to your
device and use it whenever.

<div class="grid reveal">
  <div class="card tool-cutout">
    <h3><span class="ico" aria-hidden="true">&#128228;</span>Sized to fit</h3>
    <p>Messengers cap sticker file sizes, and a sticker over the cap doesn't work. Sticker Maker checks the dimensions, byte size, duration and frame count for the target you picked, and tells you in plain words what to change.</p>
  </div>
  <div class="card tool-adjust">
    <h3><span class="ico" aria-hidden="true">&#128190;</span>Yours to keep</h3>
    <p>Exports are ordinary files on your phone. No locked library, no cloud folder, no watermark in the corner. Share the same sticker to five chats if you want.</p>
  </div>
</div>

## Sticker packs

Create a pack, give it a name, drop your exported stickers into it, reorder
them, and tag each sticker with the one to three emoji that describe it. A pack
is either static or animated (the messengers don't allow mixing), and the tray
icon is generated for you.

<div class="card reveal">
  <h3><span class="ico" aria-hidden="true">&#128230;</span>Getting a pack into a messenger</h3>
  <p><b>Add to WhatsApp</b> hands the finished pack to WhatsApp's own sticker picker, so it shows up alongside the packs you already have.</p>
  <p><b>Add to Telegram</b> sends the whole pack into Telegram with the suggested pack name, ready to pass to <b>@Stickers</b>. Telegram publishes packs through its own bot, so this is a guided handoff rather than a single tap.</p>
  <p>Either way you can still share individual stickers through the ordinary share sheet, to any app that takes an image.</p>
</div>

## Privacy

The background remover runs **on your device**, so the picture of your dog is
never uploaded, never queued on someone's server, and never seen by us.

<div class="grid reveal">
  <div class="card tool-cutout">
    <h3><span class="ico" aria-hidden="true">&#128274;</span>The app collects nothing</h3>
    <p>No account, no sign-in, no analytics SDK, no advertising ID, no crash-reporting profile of you. There is nothing to opt out of because there is nothing collected.</p>
  </div>
  <div class="card tool-text">
    <h3><span class="ico" aria-hidden="true">&#127760;</span>This website is separate</h3>
    <p>The site you're reading uses analytics only if you agree to it, and asks first. The app is a separate thing, and the <a href="{{ '/privacy/' | relative_url }}">privacy policy</a> keeps the two apart.</p>
  </div>
</div>

## Technical details

For anyone deciding whether it'll run on their phone.

- **On-device segmentation.** On Android the cut-out uses Google's ML Kit subject
  segmentation where the device provides it, and falls back to an openly
  licensed, Apache-2.0 segmentation model bundled inside the app, so the feature
  still works on devices without Google Play services. Either way, inference
  happens locally.
- **iOS is planned**, using Apple's Vision foreground-mask API on the versions
  that support it and the same bundled model elsewhere. <span class="badge soon">Planned</span>
- **512 × 512 logical canvas.** Everything you place is positioned on that
  canvas, and export re-renders the frames offscreen at the target size rather
  than screenshotting the preview, so a sticker looks the same on a small phone
  and a big one.
- **Android 8.0 (Oreo) and newer.** Portrait, dark theme, built with Flutter.
- **Fonts are bundled** under open font licences (SIL OFL and Apache-2.0), not
  fetched at runtime.

## Get it

<div class="store-badges reveal" style="margin-top:24px">
  <a class="store-badge" href="{{ site.playstore }}" rel="noopener" aria-label="Sticker Maker on Google Play">
    {% include icon-play.svg %}
    <span class="store-badge-text">
      <span class="store-badge-sub">Get it on</span>
      <span class="store-badge-name">Google Play</span>
    </span>
  </a>
  {% if site.appstore_status == "coming-soon" %}
  <span class="store-badge soon">
    {% include icon-apple.svg %}
    <span class="store-badge-text">
      <span class="store-badge-sub">Coming soon</span>
      <span class="store-badge-name">App Store</span>
    </span>
  </span>
  {% endif %}
</div>

<p class="muted" style="margin-top:14px">One purchase, every feature. No ads, no subscriptions, no in-app purchases, no watermarks.</p>

<div class="cta-row">
  <a class="btn btn-primary" href="{{ site.playstore }}" rel="noopener">Get it on Google Play</a>
  <a class="btn btn-ghost" href="{{ '/contact/' | relative_url }}">Ask a question</a>
</div>
