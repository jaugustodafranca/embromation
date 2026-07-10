// App/Sources/L10n.swift
import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
