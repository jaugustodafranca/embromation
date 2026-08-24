import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import TranslatorCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        TabView {
            GeneralTab(settings: settings, modelStore: modelStore)
                .tabItem { Label(L10n.t("settings.tab_general"), systemImage: "gearshape") }
            TranslationTab(settings: settings)
                .tabItem { Label(L10n.t("settings.tab_translation"), systemImage: "character.bubble") }
            CorrectionTab(settings: settings)
                .tabItem { Label(L10n.t("settings.tab_correction"), systemImage: "text.badge.checkmark") }
            GlossaryTab(settings: settings)
                .tabItem { Label(L10n.t("settings.tab_glossary"), systemImage: "book.closed") }
            ModelTab(settings: settings, modelStore: modelStore)
                .tabItem { Label(L10n.t("settings.tab_model"), systemImage: "cpu") }
            AboutTab()
                .tabItem { Label(L10n.t("settings.tab_about"), systemImage: "info.circle") }
        }
        .frame(width: 540)
    }
}

/// Editable base block of a prompt. The stored template is "" while the text
/// matches the built-in default, so defaults keep improving with app updates
/// until the user actually diverges; Restore just clears the override.
private struct PromptTemplateEditor: View {
    @Binding var stored: String
    let defaultTemplate: String
    let hintKey: String

    var body: some View {
        Section(L10n.t("settings.prompt")) {
            TextEditor(text: displayed)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
            Text(L10n.t(hintKey))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.t("settings.prompt_restore")) { stored = "" }
                .disabled(stored.isEmpty)
        }
    }

    private var displayed: Binding<String> {
        Binding(
            get: { stored.isEmpty ? defaultTemplate : stored },
            set: { stored = $0 == defaultTemplate ? "" : $0 }
        )
    }
}

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.t("about.app"), value: "Embromation")
                LabeledContent(L10n.t("about.version"), value: "\(version) (\(build))")
                LabeledContent(L10n.t("about.engine"),
                               value: AppleIntelligenceEngine.isSupported && SettingsData.snapshot().engine == .appleIntelligence
                                   ? L10n.t("settings.engine_apple")
                                   : L10n.t("settings.engine_local"))
            }
            Section {
                Link(L10n.t("about.website"),
                     destination: URL(string: "https://github.com/jaugustodafranca/embromation")!)
                Link(L10n.t("about.releases"),
                     destination: URL(string: "https://github.com/jaugustodafranca/embromation/releases")!)
            }
            Section {
                Text(L10n.t("about.tagline"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore
    @State private var confirmingRestore = false

    var body: some View {
        Form {
            Section(L10n.t("settings.languages")) {
                Picker(L10n.t("settings.primary"), selection: $settings.data.pair.primary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Picker(L10n.t("settings.secondary"), selection: $settings.data.pair.secondary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Text(L10n.t("settings.language_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.t("settings.general")) {
                Toggle(L10n.t("settings.launch_at_login"), isOn: launchAtLogin)
            }
            Section {
                Button(L10n.t("settings.restore_all"), role: .destructive) {
                    confirmingRestore = true
                }
                Text(L10n.t("settings.restore_all_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(L10n.t("settings.restore_all_confirm_title"),
                            isPresented: $confirmingRestore) {
            Button(L10n.t("settings.restore_all_confirm"), role: .destructive) {
                settings.restoreDefaults()
                // The reset may change the selected model/engine — recheck
                // what's on disk so the Model tab shows the right state.
                modelStore.refresh()
            }
        } message: {
            Text(L10n.t("settings.restore_all_confirm_message"))
        }
    }

    /// Spec §4.7 "iniciar no login" — backed by SMAppService (macOS 13+).
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("[embromation] launch-at-login failed: \(error)")
                }
            }
        )
    }
}

private struct TranslationTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(L10n.t("settings.shortcut")) {
                KeyboardShortcuts.Recorder(L10n.t("settings.translate_shortcut"), name: .translateSelection)
            }
            Section {
                Picker(L10n.t("settings.tone"), selection: $settings.data.tone) {
                    ForEach(Tone.allCases, id: \.self) { tone in
                        Text(L10n.t("settings.tone_\(tone.rawValue)")).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(L10n.t("settings.extra_instructions")) {
                TextField("", text: $settings.data.customInstructions,
                          prompt: Text(L10n.t("settings.extra_instructions_placeholder")),
                          axis: .vertical)
                    .labelsHidden()
                    .lineLimit(4...8)
                    .multilineTextAlignment(.leading)
            }
            PromptTemplateEditor(stored: $settings.data.translationPromptTemplate,
                                 defaultTemplate: PromptBuilder.defaultTranslationTemplate,
                                 hintKey: "settings.prompt_hint_translation")
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CorrectionTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(L10n.t("settings.correction")) {
                KeyboardShortcuts.Recorder(L10n.t("settings.fix_grammar"), name: .fixGrammar)
                Picker(L10n.t("settings.correction_flow"), selection: $settings.data.correctionReplacesDirectly) {
                    Text(L10n.t("settings.correction_popup")).tag(false)
                    Text(L10n.t("settings.correction_direct")).tag(true)
                }
                Text(L10n.t("settings.correction_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(L10n.t("settings.correction_tone"), selection: $settings.data.correctionTone) {
                    ForEach(CorrectionTone.allCases, id: \.self) { tone in
                        Text(L10n.t("settings.tone_\(tone.rawValue)")).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(L10n.t("settings.extra_instructions")) {
                TextField("", text: $settings.data.correctionInstructions,
                          prompt: Text(L10n.t("settings.correction_instructions_placeholder")),
                          axis: .vertical)
                    .labelsHidden()
                    .lineLimit(4...8)
                    .multilineTextAlignment(.leading)
            }
            PromptTemplateEditor(stored: $settings.data.correctionPromptTemplate,
                                 defaultTemplate: PromptBuilder.defaultCorrectionTemplate,
                                 hintKey: "settings.prompt_hint_correction")
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GlossaryTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var newTerm = ""

    var body: some View {
        Form {
            Section(L10n.t("settings.glossary")) {
                ForEach(settings.data.glossary, id: \.self) { term in
                    HStack {
                        Text(term).font(.body.monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            settings.data.glossary.removeAll { $0 == term }
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField(L10n.t("settings.add_term"), text: $newTerm)
                        .onSubmit(addTerm)
                    Button(L10n.t("settings.add"), action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !settings.data.glossary.contains(term) else { return }
        settings.data.glossary.append(term)
        newTerm = ""
    }
}

private struct ModelTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore

    private var selectedSpec: ModelSpec { ModelCatalog.spec(for: settings.data.selectedModelID) }
    private var physicalMemoryGB: Int { Int(ModelCatalog.physicalMemoryGB) }

    var body: some View {
        Form {
            Section(L10n.t("settings.engine")) {
                Picker(L10n.t("settings.engine"), selection: $settings.data.engine) {
                    Text(L10n.t("settings.engine_local")).tag(TranslationEngine.mlx)
                    // Below macOS 26 the option isn't offered at all — a
                    // persisted .appleIntelligence preference (e.g. settings
                    // synced from another Mac) still routes to MLX.
                    if AppleIntelligenceEngine.isSupported {
                        Text(L10n.t("settings.engine_apple")).tag(TranslationEngine.appleIntelligence)
                    }
                }
                if settings.data.engine == .appleIntelligence {
                    if let message = AppleIntelligenceEngine.unavailabilityMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Label(L10n.t("settings.engine_apple_ready"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            if settings.data.engine == .mlx {
                localModelSection
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var localModelSection: some View {
            Section(L10n.t("settings.model")) {
                Picker(L10n.t("settings.model"), selection: $settings.data.selectedModelID) {
                    ForEach(ModelCatalog.all) { spec in
                        Text("\(spec.displayName) — \(spec.approxSizeGB, specifier: "%.1f") GB")
                            .tag(spec.id)
                    }
                }
                .onChange(of: settings.data.selectedModelID) { modelStore.refresh() }

                // Warning only — the selection itself is never blocked.
                if selectedSpec.minRAMGB > physicalMemoryGB {
                    Label(String(format: L10n.t("settings.model_ram_warning"), selectedSpec.minRAMGB, physicalMemoryGB),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                switch modelStore.state {
                case .ready:
                    Label(L10n.t("settings.downloaded"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(String(format: L10n.t("settings.downloading"), progress * 100))
                            Spacer()
                            Button(L10n.t("onboarding.cancel_download")) { modelStore.cancelDownload() }
                        }
                        ProgressView(value: progress)
                    }
                case .missing, .unknown:
                    Button(L10n.t("settings.download")) { modelStore.download() }
                }
                if let message = modelStore.lastErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }

                Stepper(String(format: L10n.t("settings.unload_after"), settings.data.unloadAfterMinutes),
                        value: $settings.data.unloadAfterMinutes, in: 1...60)
            }
    }
}
