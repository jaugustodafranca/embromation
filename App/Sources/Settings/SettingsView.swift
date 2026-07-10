import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import TranslatorCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore
    @State private var newTerm = ""

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

            Section(L10n.t("settings.translation")) {
                Picker(L10n.t("settings.tone"), selection: $settings.data.tone) {
                    ForEach(Tone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("settings.extra_instructions"))
                    TextField(L10n.t("settings.extra_instructions_placeholder"),
                              text: $settings.data.customInstructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }

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

            Section(L10n.t("settings.shortcut")) {
                KeyboardShortcuts.Recorder(L10n.t("settings.translate_shortcut"), name: .translateSelection)
            }

            Section(L10n.t("settings.correction")) {
                KeyboardShortcuts.Recorder(L10n.t("settings.fix_grammar"), name: .fixGrammar)
                Picker(L10n.t("settings.correction_flow"), selection: $settings.data.correctionReplacesDirectly) {
                    Text(L10n.t("settings.correction_popup")).tag(false)
                    Text(L10n.t("settings.correction_direct")).tag(true)
                }
                Text(L10n.t("settings.correction_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("settings.model")) {
                Picker(L10n.t("settings.model"), selection: $settings.data.selectedModelID) {
                    ForEach(ModelCatalog.all) { spec in
                        Text("\(spec.displayName) — \(spec.approxSizeGB, specifier: "%.1f") GB")
                            .tag(spec.id)
                    }
                }
                .onChange(of: settings.data.selectedModelID) { modelStore.refresh() }

                switch modelStore.state {
                case .ready:
                    Label(L10n.t("settings.downloaded"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("settings.downloading"))
                        Spacer()
                        Button(L10n.t("onboarding.cancel_download")) { modelStore.cancelDownload() }
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

            Section(L10n.t("settings.general")) {
                Toggle(L10n.t("settings.launch_at_login"), isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !settings.data.glossary.contains(term) else { return }
        settings.data.glossary.append(term)
        newTerm = ""
    }
}
