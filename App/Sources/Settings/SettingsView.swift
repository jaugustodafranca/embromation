// App/Sources/Settings/SettingsView.swift
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
            Section("Languages") {
                Picker("Primary", selection: $settings.data.pair.primary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Picker("Secondary", selection: $settings.data.pair.secondary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Text("The detected language is translated to the other side of the pair.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Translation") {
                Picker("Tone", selection: $settings.data.tone) {
                    ForEach(Tone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Extra instructions", text: $settings.data.customInstructions, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Never translate these terms") {
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
                    TextField("Add term", text: $newTerm)
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Translate selection", name: .translateSelection)
            }

            Section("Model") {
                Picker("Model", selection: $settings.data.selectedModelID) {
                    ForEach(ModelCatalog.all) { spec in
                        Text("\(spec.displayName) — \(spec.approxSizeGB, specifier: "%.1f") GB")
                            .tag(spec.id)
                    }
                }
                .onChange(of: settings.data.selectedModelID) { modelStore.refresh() }

                switch modelStore.state {
                case .ready:
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading(let fraction):
                    ProgressView(value: fraction) { Text("Downloading…") }
                case .missing, .unknown:
                    Button("Download model") { Task { await modelStore.download() } }
                }
                if let message = modelStore.lastErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }

                Stepper("Unload from RAM after \(settings.data.unloadAfterMinutes) min idle",
                        value: $settings.data.unloadAfterMinutes, in: 1...60)
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
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
