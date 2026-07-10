import SwiftUI
import TranslatorCore

private struct TranslationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @State private var translationHeight: CGFloat = 0
    @State private var feedbackText = ""

    /// The text area grows with the translation up to this height, then scrolls.
    private static let maxTranslationHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            if hasFinishedTranslation {
                Divider()
                HStack(spacing: 8) {
                    TextField(L10n.t("popup.feedback_placeholder"), text: $feedbackText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitFeedback)
                    Button(L10n.t("popup.refine"), action: submitFeedback)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .onChange(of: model.phase) { _, phase in
            if phase == .working { feedbackText = "" }
        }
    }

    private var header: some View {
        HStack {
            if !model.sourceCode.isEmpty {
                Text(model.isCorrection
                     ? model.sourceCode.uppercased()
                     : "\(model.sourceCode.uppercased()) → \(model.target.code.uppercased())")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            }
            Spacer()
            Text(L10n.t("popup.local_model"))
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
                Text(L10n.t("popup.working")).foregroundStyle(.secondary)
            }
        case .noSelection:
            Text(L10n.t("popup.no_selection"))
                .foregroundStyle(.secondary)
        case .permissionNeeded:
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("popup.permission"))
                Button(L10n.t("popup.open_settings")) {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        case .streaming, .done:
            ScrollView {
                Text(model.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: TranslationHeightKey.self,
                                               value: proxy.size.height)
                    })
            }
            .frame(height: min(max(translationHeight, 22), Self.maxTranslationHeight))
            .onPreferenceChange(TranslationHeightKey.self) { translationHeight = $0 }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button(L10n.t("popup.retry")) { model.onRetry?() }
                Text(L10n.t("popup.failed_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var hasFinishedTranslation: Bool { model.phase == .done }
    private var hasTranslation: Bool { model.phase == .streaming || model.phase == .done }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { model.onCopy?() } label: {
                Text(L10n.t("popup.copy")) + Text(" ⌘C").font(.caption2).foregroundStyle(.secondary)
            }
            .disabled(!hasFinishedTranslation)
            Button { model.onReplace?() } label: {
                Text(L10n.t("popup.replace")) + Text(" ⌘⏎").font(.caption2).foregroundStyle(.secondary)
            }
            .disabled(!hasFinishedTranslation)
            if !model.isCorrection {
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
                .disabled(!hasTranslation)
            }
            Spacer()
            Text(L10n.t("popup.esc")).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func submitFeedback() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespaces)
        guard !feedback.isEmpty else { return }
        feedbackText = ""
        model.onRefine?(feedback)
    }
}
