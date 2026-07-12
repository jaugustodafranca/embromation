import Foundation

/// Serializes clipboard snapshot→mutate→restore cycles. A capture that starts
/// while a replace is still inside its paste-settle delay would interleave
/// snapshots and restores on NSPasteboard.general, silently losing the user's
/// real clipboard — so every cycle runs to completion before the next begins.
actor PasteboardQueue {
    static let shared = PasteboardQueue()

    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return await operation()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }
}
