# Localization

SwiftX ships one translation file per language. Adding or improving a language
needs **no code changes** — copy a file, translate the values, open a PR.

## Adding a language

1. Copy the English table to your language's [BCP-47 code](https://www.loc.gov/standards/iso639-2/php/code_list.php)
   (`fr`, `de`, `pt-BR`, `zh-Hans`, …):

   ```sh
   cp -R Sources/SharedKit/Resources/en.lproj Sources/SharedKit/Resources/fr.lproj
   ```

2. Translate the **values** in `fr.lproj/Localizable.strings`. Never change the
   keys, and keep every `%@` / `%d` placeholder (they are substituted at
   runtime — `%@` is text, `%d` a number — in the order given; use `%1$@`,
   `%2$@` if your language needs a different order).

   ```
   "menu.capture_region" = "Capturer une zone";
   ```

3. Validate:

   ```sh
   ./Scripts/check-localizations.sh
   ```

   This checks that every file parses and that your file has exactly the same
   key set as English. CI runs the same script on your PR.

4. Open a pull request. That's all — the language picker
   (Settings → General → Language) and the app bundle's
   `CFBundleLocalizations` discover `.lproj` directories automatically.

Untranslated keys are safe: lookups fall back to English, then to the key
itself, so a partially translated file still runs — but the checker requires
the full key set, so copy the English value for entries you haven't translated
yet rather than deleting them.

## How it works

- `L10n` (`Sources/SharedKit/L10n.swift`) resolves keys against the selected
  language's `.lproj` inside SharedKit's resource bundle, falling back to
  English, then to the key. Call sites use `L10n.t("namespace.key")` or
  `L10n.t("key", args...)` for format strings.
- The chosen language is the `InterfaceLanguage` key in
  `ApplicationConfig.json` (empty = follow macOS). It is applied once at
  startup, so changing it prompts for a relaunch. (It is deliberately not
  ShareX's `Language` key — the Windows values wouldn't round-trip.)
- The share extension bundles the same tables and follows the system
  language (the app's override lives outside its sandbox).
- `Scripts/make-app.sh` generates `CFBundleLocalizations` from the `.lproj`
  directories, and CI asserts the tables actually ship inside
  `SwiftX_SharedKit.bundle` in both the app and the appex.

## Key conventions

- Lowercase dotted namespaces, snake_case leaves: `settings.capture.show_cursor`,
  `menu.capture_region`, `alert.upload.failed_title`. Exception: `hotkey.*`
  keys use the `HotkeyType` rawValue verbatim (`hotkey.RectangleRegion`).
- `common.*` holds shared one-word labels (OK, Cancel, Save…). Reuse them;
  don't mint near-duplicates.
- Brand names (Imgur, Dropbox, GitHub, SFTP, …) are not translated and stay
  as literals in code.

## Rules for code (display vs. persistence)

Some English strings are **identity, not display** — they are stored in the
user's JSON config (ShareX-compatible) or compared for equality. Those never
change. The patterns:

- An enum whose rawValue doubles as its label gets a computed
  `var title: String { L10n.t("…") }` for display; the rawValue keeps its
  role as identity (see `SettingsPane` in `Sources/SwiftXApp/Views.swift`).
- `QuickTaskPreset` names persist in config, so the stored names stay
  English; `localizedDisplayName` translates the built-in defaults at
  display time and passes user-created names through.
- Log messages, CLI output, identifiers, URLs and persisted defaults are
  deliberately not localized.

## Not yet localized

- `Info.plist` strings (the microphone permission prompt, the Services menu
  entry, copyright). These need per-locale `InfoPlist.strings` files copied
  into `Contents/Resources/<code>.lproj/` by `Scripts/make-app.sh` — **before
  its `codesign` step**, or the seal breaks. Wire this up when the first
  non-English language lands.
- Pluralization uses simple `%d` format keys, not `.stringsdict`. If a
  language needs real plural rules, add `.stringsdict` support to `L10n`
  then.
