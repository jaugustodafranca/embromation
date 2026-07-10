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
    private var downloadTask: Task<Void, Never>?
    private var downloadGeneration = 0

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
    func download() {
        guard case .downloading = state else {
            // A model switch can knock `state` out of .downloading while an
            // old download still runs — cancel it and invalidate its writes.
            downloadTask?.cancel()
            downloadGeneration += 1
            let generation = downloadGeneration
            state = .downloading(0)
            lastErrorMessage = nil
            downloadTask = Task { await performDownload(generation: generation) }
            return
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadGeneration += 1
        refresh()
    }

    private func performDownload(generation: Int) async {
        do {
            _ = try await LLMModelFactory.shared.loadContainer(
                from: Self.downloader,
                using: Self.tokenizerLoader,
                configuration: ModelConfiguration(id: selectedSpec.id)
            ) { progress in
                Task { @MainActor in
                    guard generation == self.downloadGeneration,
                          case .downloading = self.state else { return }
                    self.state = .downloading(progress.fractionCompleted)
                }
            }
            guard generation == downloadGeneration else { return }
            // Re-derive from disk: the user may have switched models mid-download.
            refresh()
        } catch {
            guard generation == downloadGeneration else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                // cancelDownload() already refreshed; nothing to mutate here.
                return
            }
            lastErrorMessage = error.localizedDescription
            state = .missing
        }
    }
}
