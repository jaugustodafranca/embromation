# Changelog

## v1.2.0 (2026-07-13)

### Improved
- Fix grammar corrects more reliably: the model now checks a concrete list
  of error categories (capitalization, subject-verb agreement, punctuation,
  spelling) instead of a generic instruction, and reasons through the fix
  before answering rather than judging casual or technical text "good
  enough" on a skim.

## v1.1.0 (2026-07-12)

### Features
- RAM-aware default model: a fresh install now suggests the model that fits
  this Mac's memory (16 GB+ gets Qwen 3 4B, 8 GB gets Llama 3.2 3B, below
  that the light Qwen 2.5 1.5B) — and the onboarding says so.
- Settings warns when the selected model needs more RAM than this Mac has.
  Informational only: the choice is never blocked.
- Correction has its own tone setting, defaulting to "Keep original tone".
  Translation keeps its separate tone control.

### Fixed
- Correction prompts no longer promise to keep the tone while forcing another
  one — the contradiction is gone from both the main and refinement prompts.

## v1.0.1 (2026-07-12)

### Fixed
- Regenerate with feedback could answer with the refinement instruction
  itself instead of the rewritten text — worst in fix-grammar mode, where the
  proofreading contract made the model "correct" the instruction. Refinements
  now use a dedicated rewrite prompt that carries the original text, the
  previous version and the feedback as data.

## v1.0.0 (2026-07-12)

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
- Correction keeps its own extra instructions, separate from translation's.
- Emoji guard: a direct replacement that would drop or mangle an emoji is
  diverted to the popup for review instead of pasted silently.
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
