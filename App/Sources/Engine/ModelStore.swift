// App/Sources/Engine/ModelStore.swift
//
// API-drift note: the task brief targeted the 2025 mlx-swift-examples API
// (`HubApi`, `Hub.Repo`, `LLMModelFactory.shared.loadContainer(hub:configuration:progressHandler:)`).
// As of this package resolution, MLXLLM/MLXLMCommon have moved out of
// mlx-swift-examples entirely into a new package (ml-explore/mlx-swift-lm),
// and the Hugging Face download stack was rewritten around `HubClient` /
// `HubCache` (package `swift-huggingface`, module `HuggingFace`) plus a
// provider-agnostic `Downloader` / `TokenizerLoader` pair in `MLXLMCommon`.
// See task-10-report.md for the full before/after. The generation-side API
// (`ModelContainer.perform`, `UserInput`, `Chat.Message`, `MLXLMCommon.generate`,
// `.chunk`) is unchanged from the brief.
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import Tokenizers
import TranslatorCore

@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable {
        case unknown
        case missing
        case downloading(Double) // 0.0 ... 1.0
        case ready
    }

    @Published var state: State = .unknown
    @Published var lastErrorMessage: String?

    private let settings: SettingsStore

    /// All model files live under Application Support, never in the repo.
    static let cache = HubCache(cacheDirectory: URL.applicationSupportDirectory
        .appending(path: "Embromation/models"))
    static let hubClient = HubClient(cache: cache)
    static let downloader: Downloader = #hubDownloader(hubClient)
    static let tokenizerLoader: TokenizerLoader = #huggingFaceTokenizerLoader()

    init(settings: SettingsStore) {
        self.settings = settings
        refresh()
    }

    var selectedSpec: ModelSpec { ModelCatalog.spec(for: settings.data.selectedModelID) }

    func refresh() {
        state = isDownloaded(selectedSpec) ? .ready : .missing
    }

    func isDownloaded(_ spec: ModelSpec) -> Bool {
        guard let repoID = Repo.ID(rawValue: spec.id) else { return false }
        let snapshots = Self.cache.snapshotsDirectory(repo: repoID, kind: .model)
        guard let enumerator = FileManager.default.enumerator(atPath: snapshots.path) else {
            return false
        }
        for case let path as String in enumerator where path.hasSuffix(".safetensors") {
            return true
        }
        return false
    }

    /// Downloads (and warms) the selected model. Progress is published for the UI.
    func download() async {
        state = .downloading(0)
        lastErrorMessage = nil
        do {
            _ = try await LLMModelFactory.shared.loadContainer(
                from: Self.downloader,
                using: Self.tokenizerLoader,
                configuration: ModelConfiguration(id: selectedSpec.id)
            ) { progress in
                Task { @MainActor in
                    // Monotonic guard: progress callbacks hop to the main actor via an
                    // unordered `Task`, so a late `.downloading` update can otherwise land
                    // after the terminal state below (`.ready` via refresh(), or `.missing`
                    // on failure) and leave the UI stuck showing a download. Only admit the
                    // update while we're actually in `.downloading` — the synchronous
                    // `state = .downloading(0)` set above (before this loader call) is what
                    // admits the very first tick.
                    if case .downloading = self.state {
                        self.state = .downloading(progress.fractionCompleted)
                    }
                }
            }
            // Re-derive from disk for the CURRENTLY selected spec rather than assuming
            // this download's spec is still selected — the user may have switched models
            // mid-download.
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
            state = .missing
        }
    }
}
