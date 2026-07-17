# Sticker Maker — GitHub Issues Generation Plan

> **Audience:** This document is written for an AI agent (Claude Opus) whose job is to create
> GitHub **Milestones**, **umbrella (epic) issues**, and **child issues** in the repository
> `ideaconnect/sticker-maker`, so that working through the issues in order produces the finished app.
> Everything needed is in this file — product context, locked technical decisions, milestone
> definitions, per-issue specs, and the exact creation procedure (bottom of file).

---

## 1. Product summary

**Sticker Maker** (tagline: *"Make it stick."*) is a mobile app that helps people turn their own
photos into stickers for Telegram, WhatsApp and other messengers.

Canonical use case: *"I paste a photo of my dog from the park, I remove the background with one tap,
add a funny 'Woof!' caption or a comic speech bubble, and send it to my friends as a sticker.
Optionally I add more frames and export an animated GIF."*

Core features:

1. **AI background removal** — one-tap, fully on-device subject cut-out (the headline feature).
2. **Decoration** — text captions in playful display fonts (with outline/stroke), comic speech
   bubbles, per-layer adjustments (brightness / contrast / saturation / hue / opacity).
3. **Manual refinement** — erase / restore brush with adjustable size and soft edges.
4. **Animation** — multiple frames with playback speed control (2–24 fps), exported as animated
   GIF / animated WebP / Telegram-compatible WebM.
5. **Export & integration** — PNG, WebP, GIF export via the system share sheet first; native
   WhatsApp sticker-pack and Telegram sticker-pack integration in a later milestone.

## 2. Locked decisions (confirmed with the product owner)

These were explicitly confirmed by the product owner (Bartosz, bartosz@idct.tech) on 2026-07-17.
Do **not** re-open them; encode them in the issues.

| Topic | Decision |
|---|---|
| Framework | **Flutter** (Dart). Android is the primary target; iOS is a second-phase target from the same codebase. |
| AI background removal | **Hybrid**: Google **ML Kit Subject Segmentation** on Android (on-device, via Play services), **Apple Vision** foreground mask on iOS (iOS 17+), plus a **bundled open-source fallback model** (ISNet / U²-Net family, Apache-2.0) for devices without Play services and as a consistency baseline. All inference is on-device; no cloud calls. |
| Messenger integration | **Phased**: MVP exports files through the Android share sheet; a dedicated later milestone adds the WhatsApp sticker-pack intent/ContentProvider API and the best available Telegram pack-creation flow. |
| Business model | **Paid app with a minimal one-time price** on both stores. **No ads, no freemium, no in-app purchases** — every feature is included. Play Store release first, App Store second. |
| Privacy | Everything runs on-device. No accounts, no analytics SDKs collecting personal data, no image upload. This is a selling point — keep it true in every issue. |

Suggested application id: `tech.idct.stickermaker` (owner's domain is idct.tech; confirm at scaffold time).

## 3. Design reference (source of truth for UI)

The approved UI design is in this repository: **`design/Sticker Maker.dc.html`**
(a Claude Design interactive mockup; `design/support.js`, `design/image-slot.js`,
`design/android-frame.jsx` are its preview runtime). Implementers should open it in a browser and
copy visual details from its inline styles. Issues below reference it as "the design".

The design defines **three screens** in a dark theme:

1. **Home** — app logo + tagline, big gradient "New Sticker" CTA ("Start from a photo of your
   pet"), three quickstart chips (*From photo*, *Templates*, *Blank*), and a 2-column "Recent
   stickers" grid (cards with checkerboard thumbnails, GIF/PNG kind badge, name + frame/layer count).
2. **Editor** — top bar (back, project title, "512 × 512 · transparent" subtitle, undo, redo,
   gradient Export button); a square checkerboard canvas with animated dashed selection frame +
   corner handles, "Cut out" success badge, frame counter badge, and a spinner overlay
   ("Removing background…") while AI runs; a contextual bottom panel that swaps per tool; and a
   6-tab tool bar: **Layers, Adjust, Text, Erase, Cut out, Frames** (each tab has its own accent
   color — see palette below).
   - *Adjust*: five labeled sliders — Brightness, Contrast, Saturation (0–200 %), Hue (−180–180°),
     Opacity (0–100 %) — plus a Reset chip.
   - *Layers*: add button, rows with thumbnail, name, type, visibility (eye) toggle, drag handle,
     selected-row highlight.
   - *Text*: caption text field, horizontally scrolling font chips (each rendered in its own font),
     size slider 16–72 px, nine color swatches; canvas text renders with a thick contrasting
     outline (paint-order stroke) and slight rotation.
   - *Erase*: Erase/Restore mode tabs, brush size slider 8–120 px with live circular brush preview,
     "Soft edges" toggle.
   - *Cut out*: title "AI Background Removal", explainer copy, one big gradient action button
     (label cycles: "Remove background" → "Working…" → "Undo removal").
   - *Frames*: play/pause chip, horizontally scrolling 64 px frame thumbnails with active
     highlight + "add frame" dashed button, Speed slider 2–24 fps with "N fps" readout.
3. **Export** — preview thumbnail over checkerboard, **Static / Animated** segmented toggle,
   "Send to" target cards (Telegram, WhatsApp, PNG, WebP, GIF) with radio selection, dimensions +
   estimated size row, and a big gradient export CTA with progress state. A green-dot toast
   confirms actions app-wide.

**Design tokens** (from the mockup): background `#131019`, panel `#1a1624`, cards `#1c1826`/
`#221d2e`, text `#efeaf4`, muted `#8b8399`; accents — violet `#a78bfa` (Layers), cyan `#38bdf8`
(Adjust/selection), pink `#f472b6` (Text), amber `#fbbf24` (Erase), green `#34d399` (Cut out),
orange `#fb923c` (Frames); hero gradient `#7c5cff → #b06bff → #f472b6`. Fonts: **Plus Jakarta
Sans** (UI), **Fredoka** (headings), sticker fonts **Bangers, Luckiest Guy, Pacifico, Fredoka,
Rubik** (all Google Fonts, OFL-licensed — safe to bundle).

**Known design deviations to implement** (the mockup is aspirational in two places):

- The Telegram card says "Static + animated (.tgs)". `.tgs` is vector Lottie and cannot be produced
  from raster photos. Implement **WebM (VP9) video stickers** for animated Telegram export instead
  (512 px, ≤ 3 s, ≤ 256 KB, 30 fps max, no audio).
- Export size estimates ("~64 KB · WebM/GIF") are placeholders; compute real estimates.

## 4. Technical architecture (context for issue bodies)

- **Flutter** stable channel, Dart 3; single codebase, `android/` first-class, `ios/` enabled in M8.
- **State management:** Riverpod. **Navigation:** go_router. **Feature-first folder layout**
  (`lib/features/home|editor|export`, `lib/core/...`).
- **Editor document model:** a `StickerProject` = canvas (512×512 logical) + ordered `Layer` list
  (image / text / bubble) + `Frame` list (each frame owns its own layer state; "duplicate previous
  frame" is the authoring flow) + metadata. Serialized as JSON manifest + PNG assets per project in
  app documents dir.
- **Rendering:** Flutter `CustomPainter` canvas with checkerboard backdrop; final export renders
  frames offscreen via `ui.PictureRecorder` at target resolution.
- **Segmentation service:** `SegmentationEngine` interface → `MlKitEngine` (Android),
  `VisionEngine` (iOS, platform channel), `OnnxEngine` (bundled fallback). Output is an 8-bit alpha
  mask applied to the source image layer; manual erase/restore edits the same mask.
- **Encoders:** PNG/GIF via the Dart `image` package; animated WebP and WebM via native libs
  (libwebp FFI / ffmpeg-kit fork — a spike issue decides, including LGPL compliance for a paid app).
- **Format compliance targets:**
  - WhatsApp: 512×512 WebP; static ≤ 100 KB, animated ≤ 500 KB; tray icon 96×96 PNG ≤ 50 KB;
    packs of 3–30 stickers; animated total duration ≤ 10 s.
  - Telegram: static 512×512 PNG/WebP; video sticker WebM VP9 ≤ 3 s ≤ 256 KB.
  - GIF: 256-color quantization with dithering, 1-bit transparency.
- **Minimum OS:** Android 8.0 (API 26) / iOS 16 (Vision path needs 17+, fallback model below that).
- **CI:** GitHub Actions (`flutter analyze`, `flutter test`, debug APK artifact per PR; signed AAB
  release workflow in M7; macOS iOS build in M8).

---

## 5. Milestones and issues

Create milestones **in this order** (order = priority; due dates omitted intentionally).
Every milestone gets **one umbrella issue** labeled `epic` that carries a task-list of its child
issues. Child issues state acceptance criteria and link back with "Part of #\<umbrella\>".

### Labels to create first

| Label | Color (suggestion) | Purpose |
|---|---|---|
| `epic` | `#7c5cff` | Umbrella tickets |
| `area:editor` | `#38bdf8` | Canvas, layers, tools |
| `area:ai` | `#34d399` | Segmentation / models |
| `area:animation` | `#fb923c` | Frames & playback |
| `area:export` | `#fbbf24` | Encoders, share, packs |
| `area:ui` | `#f472b6` | Screens, theming, design fidelity |
| `area:infra` | `#8b8399` | CI, tooling, project setup |
| `area:release` | `#a78bfa` | Store releases, compliance |
| `platform:android` | `#3ddc84` | Android-specific |
| `platform:ios` | `#efefef` | iOS-specific |
| `spike` | `#d93f0b` | Research / decision issues |

### M0 — Foundation & tooling

**Umbrella: "Epic: Project foundation & tooling"** — Flutter scaffold, quality gates, CI, theming,
navigation. Everything later builds on this. Labels: `epic`, `area:infra`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 0.1 | Set up Flutter development environment & document it | `area:infra` | Install Flutter stable + Android SDK/toolchain on the dev machine; commit `docs/DEVELOPMENT.md` with setup steps (Windows-first), Flutter/Dart version pins, and how to run the app. AC: `flutter doctor` clean (Android part); doc reproducible. |
| 0.2 | Scaffold Flutter app | `area:infra` | `flutter create` with app id `tech.idct.stickermaker`, org name IDCT; Android minSdk 26, targetSdk latest; portrait-locked; dark-only Material theme base; remove template counter code. AC: debug APK builds and launches showing placeholder Home. |
| 0.3 | Linting, formatting & analysis gates | `area:infra` | Adopt `flutter_lints` (or `very_good_analysis`), `dart format` check, analyzer zero-warning policy. AC: documented in DEVELOPMENT.md; CI fails on violations. |
| 0.4 | CI: analyze + test + debug APK on every PR | `area:infra` | GitHub Actions workflow: checkout → Flutter setup (pinned) → `flutter analyze` → `flutter test` → build debug APK → upload artifact. AC: green run on main; badge in README. |
| 0.5 | Design system: theme, tokens & shared widgets | `area:ui` | Implement the token set from `docs/GITHUB_ISSUES_PLAN.md` §3 (colors, gradients, radii, checkerboard painter) as a Flutter `ThemeExtension`; bundle Plus Jakarta Sans + Fredoka + the 5 sticker fonts (OFL, include licenses); build shared widgets: gradient CTA button, tool tab, labeled slider row, pill chip, toast. AC: widgetbook/gallery screen or golden tests showing each widget matches the design. |
| 0.6 | Navigation shell (Home / Editor / Export) | `area:ui` | go_router routes for the three screens with placeholder bodies; editor route takes a project id; export route takes editor state. AC: can navigate Home → Editor → Export → back per the design's back/close buttons. |
| 0.7 | App icon, splash & branding | `area:ui` | App icon from the design's sparkle-in-gradient-squircle logo; adaptive icon + monochrome; splash screen with logo on `#131019`. AC: icon/splash render correctly on API 26 and latest. |

### M1 — Editor core: canvas, layers, projects

**Umbrella: "Epic: Editor canvas & project model"** — the WYSIWYG editing surface everything else
plugs into. Labels: `epic`, `area:editor`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 1.1 | Sticker project & layer data model | `area:editor` | `StickerProject`, `Layer` (image/text — bubble added in M3), `Frame`, transform (position/scale/rotation), z-order, visibility; JSON (de)serialization + versioning; unit tests. AC: round-trip serialization tests pass. |
| 1.2 | Canvas rendering engine | `area:editor` | CustomPainter rendering the 512×512 logical canvas: checkerboard, layers in z-order with transforms and per-layer opacity/color filters; scales to screen size like the design (rounded square, drop shadow). AC: golden tests for layer compositing. |
| 1.3 | Layer selection & gesture transforms | `area:editor` | Tap-to-select; drag to move, pinch to scale, two-finger/handle rotate; animated dashed selection border + 4 corner handles + top rotate handle per the design; hit-testing respects transforms. AC: manipulating layers feels correct on device; selection visuals match design. |
| 1.4 | Undo / redo system | `area:editor` | Command/snapshot-based history covering all mutating operations (add/remove/transform layer, adjust, text edits, mask edits, frame ops); top-bar buttons + toasts per design. AC: 50-step history; unit tests for grouped gestures (one gesture = one undo step). |
| 1.5 | Image import: pick, camera, paste, share-into-app | `area:editor` `platform:android` | Add image layers via gallery picker, camera capture, clipboard paste (the canonical use case!), and Android `ACTION_SEND` share-target so users can share a photo straight into a new sticker. Downscale huge images safely (EXIF rotation, memory caps). AC: all four entry paths yield a correctly-oriented image layer. |
| 1.6 | Layers panel UI | `area:editor` `area:ui` | Bottom-panel Layers tool per design: Add button, rows (thumbnail, name, type, eye toggle, drag reorder), selected highlight; rename on long-press. AC: matches design; reorder + visibility reflected live on canvas. |
| 1.7 | Adjust tool (per-layer color adjustments) | `area:editor` `area:ui` | Brightness/Contrast/Saturation (0–200 %), Hue (−180–180°), Opacity (0–100 %) sliders with accent colors + Reset, applied via color-matrix to the selected layer, live preview, undoable. AC: slider ranges/labels match design; adjustments bake correctly into export. |
| 1.8 | Project persistence & Home screen | `area:editor` `area:ui` | Save projects (JSON + assets) automatically; Home per design: New Sticker CTA, quickstart chips (From photo → opens editor with picker+Cut out tool; Templates → M3; Blank), Recent grid with real thumbnails, kind badge (GIF/PNG), frame/layer count; open/delete (long-press) projects. AC: kill-and-relaunch restores projects; Home matches design. |

### M2 — AI background removal

**Umbrella: "Epic: On-device AI background removal"** — the headline feature. Labels: `epic`,
`area:ai`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 2.1 | SegmentationEngine abstraction & mask pipeline | `area:ai` | Define `SegmentationEngine` (image in → 8-bit alpha mask out) with engine discovery/priority (system engine → bundled fallback); mask post-processing: feathering, threshold, largest-component option; apply mask to image layer non-destructively (original kept for Restore). AC: unit tests with fixture masks; engines hot-swappable. |
| 2.2 | Android: ML Kit Subject Segmentation engine | `area:ai` `platform:android` | Integrate `google_mlkit_subject_segmentation` (Play services, on-device, unbundled model download); handle model-not-yet-downloaded state, no-Play-services detection → fallback engine; process at full layer resolution. AC: dog-in-park photo cut out in ≤ 3 s on a mid-range device; graceful fallback path proven with Play services disabled. |
| 2.3 | Spike: choose bundled fallback model | `area:ai` `spike` | Evaluate ISNet/DIS, U²-Net(p), and similar **permissively-licensed** (Apache-2.0/MIT — verify each, avoid non-commercial models like RMBG-1.4) segmentation models for: license, size (target ≤ 45 MB, prefer ≤ 12 MB), quality on pets/people, CPU inference time via ONNX Runtime or LiteRT in Flutter. Deliverable: decision doc `docs/decisions/0001-fallback-model.md` + benchmark table. AC: model + runtime chosen with license files collected. |
| 2.4 | Bundled fallback engine implementation | `area:ai` | Implement `OnnxEngine` per spike 2.3 (asset-bundled model, isolate-based inference, pre/post-processing to alpha mask); wire into engine priority; setting hidden behind debug menu to force-select engine for testing. AC: same API as 2.2; works on emulator without Play services. |
| 2.5 | Cut-out tool UX | `area:ai` `area:ui` | Cut out tab per design: explainer, gradient action button with three states (Remove background / Working… / Undo removal), full-canvas spinner overlay "Removing background…", green "Cut out" badge, subtle drop-shadow on the cut subject, toasts. AC: matches design incl. state transitions; undoable. |
| 2.6 | Erase / Restore brush | `area:ai` `area:editor` | Manual mask refinement per design: Erase/Restore tabs, brush size 8–120 px with live preview circle, Soft edges toggle (hard vs feathered brush), painting edits the layer's alpha mask with pressure-independent smooth strokes; works with pan/zoomed canvas; undoable per stroke. AC: matches design; can clean up ML Kit halo artifacts. |

### M3 — Text, bubbles & templates

**Umbrella: "Epic: Text, comic bubbles & templates"** — the "Woof!" layer. Labels: `epic`,
`area:editor`, `area:ui`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 3.1 | Text layers & Text tool | `area:editor` `area:ui` | Text tool per design: caption field, 5 font chips (Bangers, Luckiest Guy, Pacifico, Fredoka, Rubik) rendered in their own font, size slider 16–72 px, 9 color swatches; canvas rendering with thick auto-contrast outline (stroke paint-order) + subtle shadow; text layers support move/scale/rotate like any layer; multiple text layers allowed. AC: matches design; "WOOF!" over a photo reproduces the mockup exactly. |
| 3.2 | Comic speech bubbles | `area:editor` `area:ui` | Bubble layer type: preset shapes (round speech, thought, shout/spiky), draggable tail anchor, fill + stroke colors from the swatch palette, optional embedded text that reflows; rendered as vector paths so they stay crisp at export. AC: classic comic "Woof!" bubble over the dog photo is achievable in ≤ 4 taps. |
| 3.3 | Templates & quickstart flows | `area:ui` | "Templates" quickstart: a small curated set (≥ 6) of pre-composed layouts (caption placement + font + bubble combos) applied to a picked photo; "Blank" creates an empty canvas; Home chips route accordingly. AC: picking a template yields an editable project; all Home quickstart chips functional. |

### M4 — Animation & frames

**Umbrella: "Epic: Animation & frames"** — multi-frame stickers. Labels: `epic`, `area:animation`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 4.1 | Frame model & timeline UI | `area:animation` | Frames tool per design: horizontal 64 px thumbnail strip with active highlight + numbered badges, dashed Add button (duplicates current frame), long-press menu (duplicate/delete/reorder); each frame owns its layer state; single-frame projects stay "static". AC: matches design; frame ops undoable; thumbnails live-update. |
| 4.2 | Playback preview & speed control | `area:animation` | Play/Pause chip and Speed slider 2–24 fps with "N fps" readout per design; playback loops on-canvas; frame counter badge ("Frame 2 / 6") on canvas while Frames tool active. AC: matches design; playback timing accurate within one frame at 24 fps. |
| 4.3 | Per-frame editing semantics | `area:animation` `area:editor` | Editing while a frame is selected affects only that frame; layer add/delete offers "apply to all frames" choice; visual indicator of which frame you're editing outside the Frames tool. AC: documented, intuitive behavior validated with a 6-frame wiggle-text sticker. |
| 4.4 | Onion skinning (nice-to-have) | `area:animation` | Ghosted previous/next frame overlay toggle to help draw motion. Mark as optional/stretch — do not block milestone completion. AC: toggle in Frames panel; ≤ 30 % opacity ghosts. |

### M5 — Export & sharing (MVP integration)

**Umbrella: "Epic: Export pipeline & sharing"** — flatten, encode, share. Labels: `epic`,
`area:export`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 5.1 | Export rendering pipeline | `area:export` | Offscreen renderer: flatten any frame at arbitrary target size (512×512 default, 1024×1024 for PNG target) with transparency, applying all layer transforms/filters/masks exactly as on-canvas; runs in isolate with progress callback. AC: golden tests comparing canvas vs export output; 8-frame render ≤ 2 s mid-range. |
| 5.2 | Static encoders: PNG & WebP + size budgets | `area:export` | Encode PNG (transparent) and WebP; iterative quality reduction to meet per-target budgets (WhatsApp static ≤ 100 KB); real size estimate shown on Export screen. AC: outputs validated against WhatsApp/Telegram static specs; unit tests for budget search. |
| 5.3 | Animated GIF encoder | `area:export` | Multi-frame GIF at chosen fps: 256-color quantization with dithering, 1-bit transparency handling (matte option for messengers that show black fringes). AC: exported GIF loops correctly in Telegram chat and Windows preview; ≤ 5 s encode for 12 frames. |
| 5.4 | Spike: animated WebP & WebM encoding strategy | `area:export` `spike` | Evaluate libwebp via Dart FFI vs maintained ffmpeg-kit forks for animated WebP (WhatsApp) and WebM VP9 (Telegram video stickers), including **LGPL compliance for a paid closed-source app** (dynamic linking) and binary size impact. Deliverable: `docs/decisions/0002-animated-encoders.md`. AC: decision + PoC encoding one animation each way. |
| 5.5 | Animated WebP & WebM encoders | `area:export` | Implement per spike 5.4: animated WebP (≤ 500 KB, ≤ 10 s, min frame duration 8 ms) and WebM VP9 (512 px, ≤ 3 s, ≤ 256 KB, ≤ 30 fps, no audio) with automatic budget enforcement (quality/fps/duration reduction with user warning). AC: files pass WhatsApp sticker validator and Telegram video-sticker constraints. |
| 5.6 | Export screen | `area:export` `area:ui` | Export screen per design: live preview (animated when applicable), Static/Animated segmented toggle, five target cards (Telegram, WhatsApp, PNG, WebP, GIF) with radio selection + per-target subtitle, dimensions & real estimated size row, gradient CTA with exporting state, success toast. Target ↔ format matrix: Telegram→PNG/WebM, WhatsApp→WebP/animated WebP, plus raw PNG/WebP/GIF. AC: matches design; all target/mode combos produce correct files. |
| 5.7 | Share sheet & save to device | `area:export` `platform:android` | Share exported file via Android share sheet (correct MIME per format); "Save to device" writes to MediaStore (Pictures/StickerMaker); handle share-target apps' quirks (Telegram receives WebM as file). AC: sharing a static sticker to Telegram/WhatsApp chat works end-to-end on device. |

### M6 — Native messenger pack integration

**Umbrella: "Epic: Sticker-pack integrations (WhatsApp & Telegram)"** — stickers that land in the
messengers' sticker pickers, not just chats. Labels: `epic`, `area:export`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 6.1 | Sticker pack model & manager UI | `area:export` `area:ui` | Local "pack" entity (name, publisher, tray icon auto-generated 96×96, 3–30 stickers, static or animated — not mixed); pack manager screen (create pack, add existing exports, reorder, delete); per-sticker emoji tagging (WhatsApp requires 1–3 emojis per sticker). AC: packs persist; validation errors surfaced inline. |
| 6.2 | WhatsApp: ContentProvider + ENABLE_STICKER_PACK intent | `area:export` `platform:android` | Implement the WhatsApp companion-app contract: `ContentProvider` serving pack metadata + WebP assets per the whatsapp-stickers sample spec, `com.whatsapp.intent.action.ENABLE_STICKER_PACK` launch flow, whitelist check, both consumer + business WhatsApp. AC: "Add to WhatsApp" from a pack lands the pack in WhatsApp's sticker picker on a real device. |
| 6.3 | Spike: Telegram pack creation UX | `area:export` `spike` | Telegram has no public client-side pack API. Evaluate: guided @Stickers-bot flow (auto-open bot, step-by-step overlay, clipboard automation), `tg://` deep links, TDLib `importStickers`, and plain share-to-Telegram. Deliverable: `docs/decisions/0003-telegram-packs.md` choosing the best legally-clean UX. AC: decision documented with fallback ranking. |
| 6.4 | Telegram pack flow implementation | `area:export` | Implement the chosen 6.3 flow, e.g. guided export: batch-export pack assets in Telegram-valid formats, open @Stickers bot with instructions overlay, then deep-link `t.me/addstickers/<name>` to install. AC: a 5-sticker pack (static + video) gets created and installed in Telegram following in-app guidance only. |
| 6.5 | Per-target compliance validation & messaging | `area:export` | Central validator (dimensions, byte budgets, duration, frame caps, emoji tags) run before any pack/share action, with human-readable fix-it messages ("Animation is 4.2 s — Telegram allows 3 s. Reduce frames or speed?"). AC: unit tests for every rule in §4 format table. |

### M7 — Android release (paid, Play Store)

**Umbrella: "Epic: Play Store release (paid app)"**. Labels: `epic`, `area:release`,
`platform:android`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 7.1 | Release signing & AAB pipeline | `area:release` `area:infra` | Upload keystore handling (secrets in GitHub Actions), `flutter build appbundle` release workflow with version bump automation, upload artifact; optionally fastlane/Gradle Play Publisher to internal track. AC: tagged commit produces a signed AAB in CI. |
| 7.2 | Play Console setup: paid listing | `area:release` | Create app (paid, minimal price tier, no ads declaration), store listing copy from product summary, category, content rating questionnaire, countries. AC: internal-track build installable by testers. |
| 7.3 | Store assets | `area:release` `area:ui` | Icon, feature graphic, ≥ 6 phone screenshots (Home, Cut out before/after, Text, Frames, Export, WhatsApp pack) shot from the real app in the design's dark theme. AC: assets uploaded and approved in Play Console. |
| 7.4 | Privacy policy & data safety | `area:release` | Privacy policy page (hosted, e.g. GitHub Pages under idct.tech): all processing on-device, no data collection; Play data-safety form matching it; license notices screen in-app (OFL fonts, Apache-2.0 model, libwebp/ffmpeg). AC: policy URL live; data-safety form consistent; licenses screen reachable from Home avatar/menu. |
| 7.5 | Performance & device QA pass | `area:release` | Test matrix: low-RAM API 26 device, 108 MP photos, 30-frame animations, no-Play-services device; fix OOMs/jank; cold start ≤ 2 s; APK/AAB size review (defer fallback model to on-demand download if > 150 MB). AC: documented QA checklist run green. |
| 7.6 | Onboarding & empty states | `area:release` `area:ui` | First-run: 2–3 screen intro (make → cut out → send) honoring the paid-premium promise (no upsells ever); empty Recent state with playful CTA; contextual first-use hints (e.g. "Tap Cut out to remove the background"). AC: fresh install to first exported sticker with zero confusion in hallway test. |
| 7.7 | Public v1.0 production release | `area:release` | Promote through internal → closed → production; tag `v1.0.0`; release notes; monitor pre-launch report & crash-free rate ≥ 99.5 %. AC: app live on Play Store as paid app. |

### M8 — iOS support & App Store release

**Umbrella: "Epic: iOS support & App Store release (paid)"**. Labels: `epic`, `platform:ios`.

| # | Issue title | Labels | Summary & acceptance criteria |
|---|---|---|---|
| 8.1 | iOS build enablement & CI | `platform:ios` `area:infra` | Enable `ios/` target, bundle id `tech.idct.stickermaker`, min iOS 16; macOS GitHub Actions job building unsigned IPA per PR; fix any plugin platform gaps found. AC: app runs on iOS simulator with feature parity except segmentation. |
| 8.2 | iOS segmentation engine (Apple Vision) | `platform:ios` `area:ai` | Platform channel to `VNGenerateForegroundInstanceMaskRequest` (iOS 17+) returning alpha mask; bundled fallback engine (2.4) used on iOS 16; same `SegmentationEngine` interface. AC: parity with Android cut-out quality on test photo set. |
| 8.3 | iOS share/export parity | `platform:ios` `area:export` | UIActivityViewController share, Photos save with permission handling, verify all encoders work on iOS (FFI binaries for arm64), WhatsApp iOS pack intent (`WAStickersThirdParty` pasteboard contract) if feasible. AC: static + animated export/share verified on device. |
| 8.4 | App Store paid release | `platform:ios` `area:release` | Signing/provisioning, App Store Connect paid listing, screenshots, privacy nutrition labels (no data collected), TestFlight, review submission; reuse privacy policy. AC: app live on App Store as paid app. |

### Backlog (create as issues without milestone, label `area:ui`)

- B.1 Emoji & prop sticker library (drop emoji/PNG props as layers).
- B.2 Sticker outline/border effect (white die-cut contour around cut-out subject — classic sticker look).
- B.3 In-app "See all" projects screen with search (Home currently shows recents only).
- B.4 Localization scaffolding (EN first; PL next given the owner's locale).
- B.5 Tablet/large-screen layout pass.

---

## 6. Creation procedure for the agent

Work in repo `ideaconnect/sticker-maker` with the `gh` CLI (already authenticated).

1. **Labels** — create every label from §5's label table:
   `gh label create "area:editor" --color 38bdf8 --description "Canvas, layers, tools"` (etc.; use
   `--force` to be idempotent).
2. **Milestones** — create M0–M8 in order via
   `gh api repos/ideaconnect/sticker-maker/milestones -f title="M0 — Foundation & tooling" -f description="<one-line scope from §5>"`;
   record each returned milestone number.
3. **Umbrella issues** — for each milestone create its epic:
   `gh issue create --title "Epic: …" --label epic,<area> --milestone "<milestone title>" --body "<scope paragraph from §5 + empty '## Tasks' section>"`.
   Record issue numbers.
4. **Child issues** — create every numbered issue in §5 with: the summary & acceptance criteria as
   body (expand telegraphic phrasing into full sentences; keep all concrete numbers, package names,
   and design references), its labels, its milestone, and a final line `Part of #<umbrella-number>`.
5. **Back-fill task lists** — edit each umbrella body to include `- [ ] #<n>` for each of its
   children (checklist in milestone order), so progress renders on the epic.
6. **Ordering note** — do not add due dates; priority is milestone order M0 → M8. Spikes (2.3,
   5.4, 6.3) must land before their dependent implementation issues (2.4, 5.5, 6.4) — state this
   dependency in those issue bodies.
7. Sanity check: 9 milestones, 9 epics, 46 child issues + 5 backlog issues. Post a summary comment
   listing everything created on the M0 epic.

**Implementation agents** picking up issues afterwards should read §2–§4 of this document and open
`design/Sticker Maker.dc.html` in a browser before writing UI code.
