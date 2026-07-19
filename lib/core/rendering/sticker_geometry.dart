/// Geometry constants shared by the two WYSIWYG rendering surfaces — the
/// on-canvas preview (`StickerCanvas`) and the headless export renderer
/// (`StickerRenderer`) — so the two painters cannot silently drift apart.
library;

/// Side length, in 512-logical canvas units, of the square box an image layer
/// is fitted (`BoxFit.contain`) into — ~0.86 of the canvas. Both painters scale
/// this by the canvas scale (target size / 512) before drawing and apply the
/// layer's own zoom on top.
///
/// This used to be a bare `440.0` literal duplicated in both painters; hoisting
/// it to one symbol is what lets the export/canvas parity test assert the two
/// paths agree by construction rather than by coincidence.
const double kStickerFitBoxSide = 440.0;
