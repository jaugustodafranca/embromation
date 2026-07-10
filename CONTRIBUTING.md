# Contributing to Embromation

Thanks for wanting to help end embromation. 🇧🇷

## Start with an issue

Before writing code, [open an
issue](https://github.com/jaugustodafranca/embromation/issues/new/choose)
using one of the templates (bug report or improvement). Agreeing on the
problem first keeps pull requests small and mergeable.

## Ground rules

The hard rules live in [AGENTS.md](AGENTS.md) and apply to every change:

1. **Privacy invariant.** The only network call in the entire app is the
   model download from Hugging Face. PRs that add network calls, telemetry,
   or analytics are rejected. No exceptions.
2. **Core is UI-free.** `TranslatorCore` never imports AppKit/SwiftUI, and
   everything the UI consumes goes through protocols.
3. **Tests never load the real model.** Use `FakeTranslator`. CI must pass
   offline.
4. Dependencies are frozen. Adding one needs written justification in the PR.

## Workflow

```bash
make test    # core suite, run it before every push
make build   # full app build (first run compiles MLX, takes minutes)
make run     # build + launch
```

- Branch from `main`, open a PR against `main`.
- `main` is protected: both CI checks must pass before merge.
- Use [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `docs:`, `ci:`, `chore:` …).
- Code, comments and docs in English. User-facing strings ship in EN and
  PT-BR. Add every new key to **both** `Localizable.strings` tables.
- The onboarding demo sentence is "The book is on the table." and it is
  load-bearing. Do not change it.
