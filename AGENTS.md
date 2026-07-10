# Embromation

macOS menu bar app that translates selected text with a **local** LLM (MLX).
Swift + SwiftUI, macOS 14+, **Apple Silicon only**. MIT licensed.

**Source of truth:** [docs/superpowers/specs/2026-07-09-embromation-design.md](docs/superpowers/specs/2026-07-09-embromation-design.md)
— read it before implementing anything.

## Project status

MVP implemented on branch `feat/first-version` (15 plan tasks complete). Manual GUI
verification checklist pending — see
`docs/superpowers/plans/2026-07-09-embromation-mvp.md` "Verification
checklist".

## Structure

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
- **Dependencies are frozen** at `ml-explore/mlx-swift-lm` (MLXLLM /
  MLXLMCommon, revision-pinned) + `sindresorhus/KeyboardShortcuts` + the
  Hugging Face download stack `mlx-swift-lm` requires (`swift-huggingface`,
  `swift-transformers`). Adding anything else requires written justification
  in the PR description.
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

- `make gen` — runs `xcodegen generate` to (re)produce `Embromation.xcodeproj`
  from `project.yml`.
- `make test` — runs the core test suite (`swift test --package-path
  TranslatorCore`). No MLX involved; nothing is downloaded.
- `make build` — `gen` then a Debug build of the `Embromation` scheme
  (`xcodebuild ... -skipMacroValidation`). `-skipMacroValidation` is required
  because `mlx-swift-lm`'s `MLXHuggingFace` target uses Swift macros
  (`#hubDownloader` / `#huggingFaceTokenizerLoader`) that Xcode otherwise
  refuses to run without an interactive "Trust & Enable" prompt.
- `make run` — `build` then opens the built `.app`.

The first build downloads and compiles the full MLX stack, which takes
several minutes. On a fresh machine, run
`xcodebuild -downloadComponent MetalToolchain` before building — without the
Metal toolchain, the MLX targets fail to compile.
