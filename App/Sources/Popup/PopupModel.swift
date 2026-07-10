import Foundation
import TranslatorCore

@MainActor
final class PopupModel: ObservableObject {
    enum Phase: Equatable {
        case working            // capturing / preparing model
        case noSelection
        case permissionNeeded
        case streaming
        case done
        case failed(String)
    }

    @Published var phase: Phase = .working
    @Published var text = ""
    @Published var sourceCode = ""
    @Published var target: Language = .portuguese

    // Wired by the coordinator:
    var onRetarget: ((Language) -> Void)?
    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
    var onRetry: (() -> Void)?
}
