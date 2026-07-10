# Release Pipeline Implementation Plan (v1.0.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tag-triggered GitHub Actions workflow that builds a signed, notarized, stapled DMG and publishes it as a GitHub Release — then ship v1.0.0.

**Architecture:** One new workflow (`release.yml`) mirroring `ci.yml`'s proven build recipe (macos-26, Metal guard, skip-validation flags, DerivedData cache) plus: temp-keychain certificate import from secrets, Release-configuration signed build, notarization of the zipped app (staple), `hdiutil` DMG (no third-party DMG tools), notarization of the DMG (staple), `gh release create` with the asset. Versioning comes from the tag; `project.yml`'s MARKETING_VERSION is bumped to match.

**Spec basis:** original design doc §8 (Distribuição) — `docs/superpowers/specs/2026-07-09-embromation-design.md`. Homebrew cask and Sparkle auto-update stay out of scope (post-1.0).

**Branch:** `feat/release-pipeline`.

## Global Constraints

- Secrets already configured on the repo (same names as keybinder): `MAC_CERTIFICATE_P12_BASE64`, `MAC_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` (= 688YYDN5Z4).
- Signing identity: `Developer ID Application: Zaintech LTDA (688YYDN5Z4)`; hardened runtime already ON in project.yml.
- The workflow must NEVER download the 2.3GB model (nothing in it runs the app).
- No new tooling deps: `hdiutil`, `codesign`, `notarytool`, `stapler`, `ditto`, `gh` — all preinstalled on the runner.
- Tag format: `v*` (e.g. `v1.0.0`, prerelease `v1.0.0-rc.1` → marked prerelease automatically when the tag contains a hyphen).
- ORDERING: the repo must be flipped PUBLIC before the final `v1.0.0` release is published (release assets on a private repo aren't downloadable by the public). RC dry-runs may happen while private.
- Conventional commits; version-bump changes go to main via PR (protected branch).

---

### Task 1: Version bump, changelog and install docs

**Files:**
- Modify: `project.yml` (MARKETING_VERSION `0.1.0` → `1.0.0`)
- Create: `CHANGELOG.md`
- Modify: `README.md` (Install section + status line)

- [ ] **Step 1: project.yml**

Change `MARKETING_VERSION: 0.1.0` to `MARKETING_VERSION: 1.0.0` (leave CURRENT_PROJECT_VERSION at 1).

- [ ] **Step 2: CHANGELOG.md**

```markdown
# Changelog

## v1.0.0 — 2026-07-10

First public release. 🇧🇷

### Features
- Instant on-device translation (⌃T): select text in any app, get a streaming
  translation in a floating popup. Auto-detected language pair, one hotkey
  for both directions.
- Fix grammar (⌃G): proofreading mode that corrects grammar, spelling and
  punctuation keeping the language, meaning and tone.
- Feedback loop: tell the model what to improve and regenerate, right in the
  popup. Session-only — nothing is stored or sent anywhere.
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
  from Hugging Face. No accounts, no API keys, no telemetry — auditable in
  this repository.

Requires macOS 14+ on Apple Silicon.
```

- [ ] **Step 3: README Install section**

After the feature bullet list, add:

```markdown
## Install

1. Download the latest `Embromation-x.y.z.dmg` from
   [Releases](https://github.com/jaugustodafranca/embromation/releases).
2. Drag **Embromation** to Applications and launch it.
3. Follow the 3-step welcome guide (Accessibility permission + one-time
   ~2.3 GB model download).

The app is signed and notarized. It lives in your menu bar — select text
anywhere and press **⌃T** to translate or **⌃G** to fix grammar.
```

Also change the Status line to: `**Status:** ✅ v1.0.0 — see [CHANGELOG.md](CHANGELOG.md).`

- [ ] **Step 4: Verify** — `make test` (28) and `make build` still green (version bump only).

- [ ] **Step 5: Commit**

```bash
git add project.yml CHANGELOG.md README.md
git commit -m "chore: bump to 1.0.0 with changelog and install docs"
```

---

### Task 2: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write # create the GitHub Release

jobs:
  release:
    name: Signed DMG release
    # macos-26 carries Xcode 26 — same rationale as ci.yml.
    runs-on: macos-26
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Download Metal toolchain
        run: |
          xcodebuild -version
          if xcodebuild -help 2>/dev/null | grep -q downloadComponent; then
            xcodebuild -downloadComponent MetalToolchain
          else
            echo "Metal toolchain bundled with this Xcode — skipping"
          fi

      - name: Import signing certificate
        env:
          MAC_CERTIFICATE_P12_BASE64: ${{ secrets.MAC_CERTIFICATE_P12_BASE64 }}
          MAC_CERTIFICATE_PASSWORD: ${{ secrets.MAC_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PASSWORD=$(uuidgen)
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security set-keychain-settings -lut 7200 build.keychain
          echo "$MAC_CERTIFICATE_P12_BASE64" | base64 --decode > cert.p12
          security import cert.p12 -k build.keychain \
            -P "$MAC_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: \
            -s -k "$KEYCHAIN_PASSWORD" build.keychain
          rm cert.p12

      - name: Generate project
        run: xcodegen generate

      - name: Cache compiled dependencies
        uses: actions/cache@v4
        with:
          path: .build/DerivedData
          key: derived-data-release-${{ runner.os }}-${{ hashFiles('project.yml') }}
          restore-keys: derived-data-release-${{ runner.os }}-

      - name: Build signed Release app
        run: |
          xcodebuild -project Embromation.xcodeproj -scheme Embromation \
            -configuration Release -derivedDataPath .build/DerivedData \
            -skipMacroValidation -skipPackagePluginValidation build
          APP=".build/DerivedData/Build/Products/Release/Embromation.app"
          codesign --verify --deep --strict "$APP"
          codesign -dvv "$APP" 2>&1 | grep "Developer ID Application"

      - name: Notarize and staple the app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          APP=".build/DerivedData/Build/Products/Release/Embromation.app"
          ditto -c -k --keepParent "$APP" Embromation.zip
          xcrun notarytool submit Embromation.zip --wait \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID"
          xcrun stapler staple "$APP"

      - name: Build, sign, notarize and staple the DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          APP=".build/DerivedData/Build/Products/Release/Embromation.app"
          VERSION="${GITHUB_REF_NAME#v}"
          DMG="Embromation-${VERSION}.dmg"
          mkdir dmg-root
          cp -R "$APP" dmg-root/
          ln -s /Applications dmg-root/Applications
          hdiutil create -volname "Embromation" -srcfolder dmg-root \
            -ov -format UDZO "$DMG"
          codesign --sign "Developer ID Application" "$DMG"
          xcrun notarytool submit "$DMG" --wait \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID"
          xcrun stapler staple "$DMG"
          echo "DMG=$DMG" >> "$GITHUB_ENV"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          EXTRA=""
          case "$GITHUB_REF_NAME" in
            *-*) EXTRA="--prerelease" ;;
          esac
          gh release create "$GITHUB_REF_NAME" "$DMG" \
            --title "Embromation $GITHUB_REF_NAME" \
            --generate-notes $EXTRA
```

- [ ] **Step 2: Validate YAML**

Run: `ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml'); puts 'valid'"`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: tag-triggered signed and notarized DMG release"
```

---

### Task 3: Open PR, merge, and RC dry-run (controller-driven)

- [ ] **Step 1:** Push branch, open PR "ci: release pipeline + v1.0.0 bump", wait for CI green, merge.
- [ ] **Step 2:** Tag the dry run from updated main:

```bash
git checkout main && git pull
git tag v1.0.0-rc.1 && git push origin v1.0.0-rc.1
```

- [ ] **Step 3:** Watch the Release workflow (`gh run watch`). Expected hot spots, in order: keychain import (secret validity — first real test of the .p12), signed build, notarytool (first submission can take a few minutes; `--wait` handles it), stapling, release created as PRERELEASE.
- [ ] **Step 4:** Verify locally on the author's machine:

```bash
gh release download v1.0.0-rc.1 --pattern '*.dmg' --dir /tmp/rc
spctl -a -t open --context context:primary-signature -v /tmp/rc/Embromation-*.dmg   # expect: accepted
hdiutil attach /tmp/rc/Embromation-*.dmg
spctl -a -vv /Volumes/Embromation/Embromation.app                                   # expect: accepted, Notarized Developer ID
hdiutil detach /Volumes/Embromation
```

- [ ] **Step 5:** Fix loop if anything fails (workflow edits go via PR to main; re-tag rc.2 etc.). Delete rc releases/tags after success:

```bash
gh release delete v1.0.0-rc.1 --yes && git push origin :v1.0.0-rc.1 && git tag -d v1.0.0-rc.1
```

---

### Task 4: Go public and ship v1.0.0

- [ ] **Step 1 (author consent already given for the destination — confirm at execution):** flip visibility:

```bash
gh repo edit jaugustodafranca/embromation --visibility public --accept-visibility-change-consequences
```

- [ ] **Step 2:** Tag the real release from main: `git tag v1.0.0 && git push origin v1.0.0` — watch to green.
- [ ] **Step 3:** Sanity: release page shows the DMG, `--generate-notes` content sane, README renders with Install section, issue templates appear in the New Issue chooser.
- [ ] **Step 4:** Author installs FROM THE DMG (the real first-user experience — Gatekeeper must not warn) and runs the onboarding once on the release build.
- [ ] **Step 5:** Backlog issues (post-1.0): Homebrew cask, Sparkle auto-update, ⌘C-in-feedback-field hijack, MLXTranslator double-load reentrancy, prompt-lines DRY, unlocalized Tone/Language picker names.

## Verification checklist

1. RC workflow green end-to-end on first or second attempt.
2. `spctl` accepts both DMG and app (Notarized Developer ID).
3. v1.0.0 release public with DMG attached; download works logged-out.
4. Fresh install from DMG: no Gatekeeper warning, onboarding works, ⌃T/⌃G work.
