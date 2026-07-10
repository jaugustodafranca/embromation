// App/Sources/Popup/PopupView.swift
import SwiftUI
import TranslatorCore

struct PopupView: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            Divider()
            footer
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private var header: some View {
        HStack {
            Text("\(model.sourceCode.uppercased()) → \(model.target.code.uppercased())")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.tint.opacity(0.15)))
            Spacer()
            Text("local model")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(.secondary)
            }
        case .noSelection:
            Text("No text selected — select something and press the shortcut again. Tip: if the app blocks capture, copy the text (⌘C) and retry.")
                .foregroundStyle(.secondary)
        case .permissionNeeded:
            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility permission is required to capture selected text.")
                Button("Open System Settings…") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        case .streaming, .done:
            ScrollView {
                Text(model.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { model.onRetry?() }
                Text("If this keeps happening, try the lighter model in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy") { model.onCopy?() }
                .disabled(model.phase != .done)
            Button("Replace") { model.onReplace?() }
                .disabled(model.phase != .done)
            Picker("", selection: Binding(
                get: { model.target },
                set: { model.onRetarget?($0) }
            )) {
                ForEach(Language.all, id: \.code) { lang in
                    Text(lang.englishName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .disabled(!(model.phase == .streaming || model.phase == .done))
            Spacer()
            Text("esc closes").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
