# Correction Tone — Tech Plan

**Dev**: Bob
**Date**: 2026-07-12
**Branch**: `feat/correction-tone`
**Based on spec**: task brief given directly (no separate `spec.md` for this slug — the
brief in the task description is the source of truth for WHAT; this covers HOW).

## Approach

Give proofreading (⌃G) its own tone setting, independent from the translation tone,
defaulting to "keep whatever tone the input already has." Thread a new `CorrectionTone`
enum through `SettingsData` → `TranslationRequest` → `PromptBuilder`, and branch the two
correction prompt builders (`correctionPrompt`, and the `.correct` arm of
`refinementPrompt`) on it instead of unconditionally forcing the translation `Tone`.
Additive changes only: `TranslationRequest.correctionTone` defaults to `.keep`, so every
existing call site (translate mode, tests, coordinator's `retarget`) keeps compiling
without modification.

## Files to touch

- `TranslatorCore/Sources/TranslatorCore/CorrectionTone.swift` — new file. One type per
  file matches the existing convention (`Tone.swift`, `Language.swift`, …).
- `TranslatorCore/Sources/TranslatorCore/SettingsStore.swift` — modified: new
  `correctionTone` field + CodingKey + tolerant decode line.
- `TranslatorCore/Sources/TranslatorCore/StreamingTranslator.swift` — modified:
  `TranslationRequest.correctionTone` (defaulted), in both the stored property and the
  custom `init`.
- `TranslatorCore/Sources/TranslatorCore/PromptBuilder.swift` — modified:
  `correctionPrompt` takes `correctionTone: CorrectionTone` instead of `tone: Tone`;
  `refinementPrompt`'s tone-clause append becomes mode-aware.
- `TranslatorCore/Tests/TranslatorCoreTests/CorrectionTests.swift` — modified + new
  cases (keep vs. formal permutations for the plain correction prompt).
- `TranslatorCore/Tests/TranslatorCoreTests/PromptBuilderTests.swift` — modified + new
  case (keep vs. formal for the refinement variant), one call-site signature update.
- `TranslatorCore/Tests/TranslatorCoreTests/SettingsStoreTests.swift` — new migration
  test + one assertion added to the defaults test.
- `App/Sources/TranslationCoordinator.swift` — modified: pass `correctionTone` at the
  one `TranslationRequest(...)` construction site in `run(mode:)`.
- `App/Sources/Settings/SettingsView.swift` — modified: `CorrectionTab` gets a tone
  picker (segmented, same style as `TranslationTab`'s).
- `App/Resources/en.lproj/Localizable.strings`, `App/Resources/pt-BR.lproj/Localizable.strings`
  — 2 new keys each: `settings.correction_tone`, `settings.tone_keep`.

## Data model / API changes

- `CorrectionTone: String, CaseIterable, Codable, Sendable` — cases `keep, neutral,
  formal, casual`. `promptClause: String?` returns `nil` for `.keep`, else delegates to
  the matching `Tone.promptClause` (`.neutral`/`.formal`/`.casual` mirror `Tone` 1:1).
- `SettingsData.correctionTone: CorrectionTone = .keep` — tolerant-decoded like every
  other field; an old persisted blob without the key decodes to `.keep`.
- `TranslationRequest.correctionTone: CorrectionTone = .keep` — defaulted parameter,
  additive.
- `PromptBuilder.correctionPrompt(language:correctionTone:customInstructions:glossary:)`
  — **signature change**, replacing the `tone: Tone` parameter. This is a breaking
  source change for the 3 existing call sites (2 in `CorrectionTests.swift`, 1 in
  `PromptBuilderTests.swift`); all 3 are updated as part of this change per the task's
  instruction to fix tests asserting the old contradictory shape.

## Design decision: exact prompt-branching shape

The task pins down the plain `correctionPrompt` line precisely (it quotes the existing
string verbatim: `"keeping the same language (X), meaning and tone."` →
`"keeping the same language (X) and meaning."`). That exact string only lives in
`correctionPrompt`; `refinementPrompt`'s `.correct` arm has always had different wording
("same language (X), same meaning —") that never mentioned tone in the text — the bug
there is purely the unconditional `lines.append(request.tone.promptClause)` after the
switch, using the *translation* tone regardless of mode. Decision: leave both
mode-specific opening lines in `refinementPrompt` textually untouched (minimal diff, no
new contradiction was ever in that sentence), and make only the trailing tone-clause
append mode-aware:
- `.translate` → unchanged, still `request.tone.promptClause` unconditionally.
- `.correct` → `.keep` appends nothing; otherwise appends `request.correctionTone.promptClause`.

This is a judgment call, not a business-intent question, so I'm not escalating it to
`@pm`/`@user` — it's the smaller, more surgical diff and it fully removes the coupling
to the translation tone for correction, which is the actual bug.

## Risks

- **Signature break is source-only, not binary** — `TranslatorCore` has no external
  consumers besides `App` and its own test target, both updated in this branch. Low risk.
- **Settings migration** — must not reset existing users' persisted tone/instructions
  when `correctionTone` is absent from old JSON. Mitigated by tolerant decoding
  (existing pattern) + a dedicated test with an old-shaped blob.
- **String-matching tests are brittle** — `PromptBuilder` tests assert on substrings of
  hand-written prompt text; any future copy edit to these lines needs matching test
  updates. Pre-existing risk in this codebase, not introduced here.
- Nothing touches the model/inference layer, network, or persistence format version —
  no `storageKey` bump needed (tolerant decoding handles the new field).

## Alternatives considered

- **Reuse `Tone` directly for correction, with a separate `Bool keepCorrectionTone`
  flag** instead of a 4-case `CorrectionTone` enum. Rejected: the task explicitly asks
  for a `CorrectionTone` enum with a `.keep` case, and a bool+Tone pair is a weaker
  model (two independent settings can represent invalid combinations the enum can't).
- **Give `refinementPrompt`'s `.correct` line the exact same phrase-swap as
  `correctionPrompt`** (rewrite "same language (X), same meaning" to parallel the
  keep/non-keep phrasing used in `correctionPrompt`). Rejected in favor of the minimal
  diff above — the refinement line's bug is purely the trailing unconditional append,
  not a textual self-contradiction, so rewriting it would be an unrequested cosmetic
  change to text that wasn't broken.

## Open technical questions

None blocking. The one interpretive call (prompt-branching shape above) is small
enough to make directly; flagging it in the PR description for visibility rather than
pausing for review.

## Test strategy

- TDD for `PromptBuilder`: write the new/updated tests first (keep vs. formal, for both
  `correctionPrompt` and the `.correct` refinement variant), confirm they fail to build
  (the new `correctionTone:` label doesn't exist yet — in a statically typed language
  this is the "red" state), then implement `PromptBuilder` to turn them green.
  Translation-mode tests are untouched and must stay green throughout (regression
  guard that `tone` handling for `.translate` never moves).
- `SettingsStoreTests`: new test decodes an old-shaped JSON blob (no `correctionTone`
  key, but with `correctionReplacesDirectly` present — i.e. the last shipped shape) and
  asserts it defaults to `.keep` without disturbing sibling fields.
- App layer (`TranslationCoordinator`, `SettingsView`) has no dedicated unit tests in
  this codebase (no XCTest target over `App/`); verified via `make build`
  (BUILD SUCCEEDED) and manual code reading — consistent with how `correctionReplacesDirectly`
  and other Settings-tab fields were verified previously.
- Full `make test` (all TranslatorCore tests green) + `make build` (BUILD SUCCEEDED) as
  final gates. Real model is never invoked (per AGENTS.md hard rule).
