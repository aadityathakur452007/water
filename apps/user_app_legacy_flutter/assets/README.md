# Assets (F3 staged, F1 integrates)

Copied (approved spec answer 1): ONLY `logo.png` + `20l.jpg` from `public/`.
Skipped: `20l.png` (1.7MB, too heavy for the app bundle) and `1l.png`
(not needed by home + booking screens).

## For the integrator (F1 — pubspec owner)

`pubspec.yaml` is F1-owned — F3 does NOT edit it. Add exactly this block
under the `flutter:` section:

```yaml
  assets:
    - assets/logo.png
    - assets/20l.jpg
```

Then run `flutter pub get`. Both paths are referenced as
`assets/logo.png` / `assets/20l.jpg` from `lib/features/booking/`
with `errorBuilder` fallbacks, so the UI renders even before this lands.
