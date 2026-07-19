# Agent / contributor rules

## Before every commit (required)

1. **Format:** run `dart format .` and re-stage — the check that must pass is:

   ```
   dart format --set-exit-if-changed .
   ```

   A commit that changes `.dart` files without being format-clean is not acceptable; CI and reviewers treat formatter drift as a broken build.
2. **Analyze:** `flutter analyze` must report no issues.
3. **Test:** `flutter test` must be green (goldens are tagged `golden` and excluded by default; regenerate deliberately with `flutter test --tags golden --update-goldens`).

## Repo constraints

- Paid, closed-source app: GPL/AGPL/non-commercial dependencies are forbidden; LGPL only with dynamic linking (the pinned `ffmpeg_kit_flutter_new_video` "video" tier is the vetted example — never switch it to the default GPL package).
- Never add code that auto-downloads ML model weights; models are vetted and bundled by the maintainer (see `assets/models/README.md`).
