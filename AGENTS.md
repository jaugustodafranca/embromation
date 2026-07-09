# Embromation

macOS menu bar app that translates selected text with a **local** LLM (MLX).
Swift + SwiftUI, macOS 14+, **Apple Silicon only**. MIT licensed.

**Source of truth:** [docs/superpowers/specs/2026-07-09-embromation-design.md](docs/superpowers/specs/2026-07-09-embromation-design.md)
— read it before implementing anything.

## Project status

Pre-code: design approved, implementation plan pending. Update this file
(build commands, real structure) as soon as scaffolding lands.

## Structure (planned)

- `App/` — SwiftUI target: `MenuBar/`, `Popup/` (non-activating NSPanel), `Settings/`, `Onboarding/`
- `TranslatorCore/` — Swift Package with **no UI dependencies**: `InferenceEngine`, `ModelManager`, `PromptBuilder`, `LanguageDetector`, `SelectionCapture`
- `.github/workflows/` — CI (build + test), release (sign/notarize + DMG)

## Hard rules

- **Core is UI-free.** `TranslatorCore` never imports AppKit/SwiftUI. Foundation and
  NaturalLanguage are allowed. Everything the UI consumes goes through protocols
  (e.g. `StreamingTranslator`) so tests can fake it.
- **Privacy invariant.** The ONLY network call in the entire app is the model
  download from Hugging Face. No telemetry, no analytics, no phoning home.
  Changes that add network calls are rejected.
- **Never load the real model in tests.** Use the `StreamingTranslator` fake.
  CI must pass without downloading anything from Hugging Face.
- **Dependencies are frozen** at `mlx-swift-examples` (MLXLLM) and
  `sindresorhus/KeyboardShortcuts`. Adding a dependency requires written
  justification in the PR description.
- **Concurrency:** async/await and actors. No completion handlers; no
  DispatchQueue unless bridging AppKit demands it.
- **Localization:** user-facing strings ship in EN and PT-BR from day one.
- **Errors:** every user-visible failure has a recovery action (retry, open
  settings, …) — see spec §6.

## Conventions

- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:` …).
- Code, comments, and docs in English. The README keeps the bilingual jokes.
- The onboarding demo sentence is **"The book is on the table."** — do not
  change it; it is load-bearing (spec §4.8).

## Build

To be filled when the Xcode project exists. Until then, there is nothing to build.
