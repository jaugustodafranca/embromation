// App/Sources/Popup/PopupModel.swift
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

    // Wired by the coordinator / controller:
    var onRetarget: ((Language) -> Void)?
    var onCopy: (() -> Void)?      // implemented in Task 11
    var onReplace: (() -> Void)?   // implemented in Task 11
    var onRetry: (() -> Void)?
}
