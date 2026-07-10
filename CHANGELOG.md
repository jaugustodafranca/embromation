# Changelog

## v1.0.0 (2026-07-10)

First public release. 🇧🇷

### Features
- Instant on-device translation (⌃T): select text in any app, get a streaming
  translation in a floating popup. Auto-detected language pair, one hotkey
  for both directions.
- Fix grammar (⌃G): proofreading mode that corrects grammar, spelling and
  punctuation keeping the language, meaning and tone.
- Feedback loop: tell the model what to improve and regenerate, right in the
  popup. It lives only in that popup session and nothing is stored or sent anywhere.
- Configurable correction flow: review in the popup or replace your selection
  directly.
- Tone control (neutral/formal/casual), free-form instructions, and a
  glossary of terms that must never be translated.
- Popup shortcuts: ⌘C copies, ⌘⏎ replaces. Esc closes.
- 3-step onboarding with local model download (Qwen 3 4B via MLX), honest
  progress and cancel/retry.
- Fully localized: English and Brazilian Portuguese.

### Privacy
- The ONLY network call in the entire app is the one-time model download
  from Hugging Face. No accounts, no API keys, no telemetry. You can audit all of it in
  this repository.

Requires macOS 14+ on Apple Silicon.
