# M0 review — items deferred to M1

The M0 foundation went through a multi-agent adversarial review (design fidelity,
Flutter/Dart correctness, runtime robustness, architecture). 13 findings were fixed in M0
(navigation back-stack, router disposal, sticker-caption outline, cut-out button contrast +
undo state, Frames play/pause, slider value colors, erase brush preview, panel header hints,
font-chip radius, `sm_toast` timer/animation leak + coalescing, editor keyboard overflow,
gallery route guarded behind `kDebugMode`).

The following **architecture** findings were intentionally deferred to **M1**, because M1 is where
the editor engine and data model are built (issues #17–#24). Doing them in M0 and rewriting them in
M1 would be waste. They are recorded here so they are not lost.

## D1 — Introduce the Riverpod state/domain layer (blocks: #17, #20)

`ProviderScope` is installed but unused; `_EditorScreenState` holds ~19 flat `setState` fields with
no `StickerDocument`/`Layer` model, and Undo/Redo are wired to toasts. **M1 must** introduce an
immutable document model + a Riverpod `EditorController`, and convert `EditorScreen` to a
`ConsumerWidget`. Lock in immutable snapshots so undo/redo (issue #20) can be layered on cheaply.
Until then the Undo/Redo buttons are placeholders (show a toast) — acceptable for the M0 shell.

## D2 — Extract an `EditorTool` domain enum (blocks: #17)

The tool set is currently modeled by `SmAccent` (a theme/color enum) in the theme layer, with tool
label/icon hardcoded again in the tool bar. M1 should introduce an `EditorTool` value type
(carrying `tabLabel`, `panelTitle`, `icon`, `accent`) as the single source of truth, and reduce
`SmAccent` to a pure color key. Drive the tool bar and panel switch from one ordered list.

## D3 — Centralize fixture data + shared models (blocks: #17, #1.8)

Sample data is hardcoded across widgets (`_sampleProjects` in home, tuple layers in the editor,
inline export dimensions), and the project title "Rex woof" is duplicated. M1 should define shared
value types (`StickerProject` with `enum StickerKind`, `Layer` with `enum LayerType`,
`ExportTarget`) in `core/models` and serve fixtures from a provider, so the eventual repository swap
is a provider override rather than edits across four files.

## D4 — Data/service seam for M2 (AI) and persistence (blocks: #2.1, #1.8)

There is no `data/`/`services/`/repository layer. Before M2 (on-device segmentation) and project
persistence land, add a service seam so ML inference, image I/O, and (M5) encoders don't leak into
widgets. `SegmentationEngine` (issue #2.1) is the first such service.

## Optional / low priority

- `SmTokens` exposes only a subset of the palette; widgets read `AppColors` directly. For this
  dark-only app that is acceptable (the `AppColors` doc now says so). If theming is ever added,
  complete `SmTokens` and migrate call sites.
