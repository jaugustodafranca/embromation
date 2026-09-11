# Changelog

## v1.4.0 (2026-09-11)

### Features
- New recommended local model: Qwen 3 4B Instruct (2507). Same size and
  speed as the previous default, no reasoning mode, and it fixes more
  grammar than the old model did — including subject-verb agreement and
  missing auxiliaries ("I struggling" → "I'm struggling"). Settings marks it
  as recommended and offers a one-click switch; existing installs keep
  their current model until they switch.
- Editable prompts: the translation and correction instructions are now
  plain text you can edit in Settings, with Restore default. Tone pickers
  and extra-instruction fields are gone — the prompt owns them now.
- Restore all settings to defaults (General tab) and an About tab.
- Apple Intelligence: when its guardrails decline an ordinary message, the
  request transparently retries on the local model, and the popup names the
  engine that served it.

### Improved
- Fix grammar is 5–30× faster. Since v1.2.0 the local model was writing
  300–2 300 hidden reasoning tokens before every correction (up to ~30 s
  with nothing on screen); corrections now answer directly, in 1–3 s.
- Corrections are deterministic: the same text always gets the same fix.
- The model stays loaded for 30 minutes of inactivity instead of 10, so a
  normal working session no longer pays the ~1.5 s reload.
- Local builds are Release by default (`make run`); Debug generated tokens
  at a third of the speed.

### Fixed
- Question-shaped input ("report carries a bookingId?") was answered instead
  of translated or corrected; code identifiers (bookingId, user_id) were
  translated; terse messages were shortened or flattened from a question
  into a statement.
- Output no longer invents Markdown emphasis the input never had; it mirrors
  the message's own formatting.

## v1.3.0 (2026-08-24)

### Features
- Apple Intelligence engine (macOS 26+): a new Engine option in Settings
  uses the Mac's built-in on-device model — no multi-GB download, near
  instant load, and noticeably faster corrections. Everything stays local.
  The downloaded local models remain the default and the only option on
  older systems.

### Improved
- Fix grammar now also rewrites awkwardly worded sentences to read the way
  a native speaker would phrase them — while never changing the meaning
  (nothing added, nothing removed, intent untouched).
- Corrections on the local engine are much faster: the reasoning pass was
  running with sampling settings that Qwen3 explicitly warns against,
  which could spiral into a ~100-second loop before answering.

## v1.2.1 (2026-07-14)

### Fixed
- The popup no longer spins forever with no explanation when the selected
  model hasn't been downloaded yet — it now points you at Settings to
  download it.
- Settings and the onboarding download step now show the actual download
  percentage instead of a bare spinner.
- Fixed a leading space/line break sometimes appearing before corrected or
  translated text, introduced by the v1.2.0 reasoning pass.

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
