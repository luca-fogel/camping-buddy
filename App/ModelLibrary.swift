import Foundation
import SwiftUI

@MainActor
final class ModelLibrary: ObservableObject {
    let catalog: ModelCatalog
    let storage: ModelStorage
    @Published private(set) var inventory: [InstalledModel] = []
    @Published private(set) var selectedID: String
    @Published private(set) var downloads: [String: ModelDownloadState] = [:]
    @Published private(set) var isInitialized = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var availableDiskBytes: Int64?
    @Published var error: String?

    private let downloader: ModelDownloader
    private var preparation: Task<Void, Never>?
    private var tasks: [String: Task<Void, any Error>] = [:]
    private var ownedIDs = Set<String>()
    @Published private var protectedIDs = Set<String>()

    init(catalog: ModelCatalog, storage: ModelStorage) {
        self.catalog = catalog; self.storage = storage
        self.selectedID = catalog.defaultModelID
        self.downloader = ModelDownloader(storage: storage)
    }

    static func bundled() throws -> ModelLibrary {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ModelCatalog") else {
            throw ModelCatalogError.invalid("The model catalog is missing from this build.")
        }
        let catalog = try ModelCatalog(data: Data(contentsOf: url))
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let storage = try ModelStorage(catalog: catalog,
                                       rootDirectory: support.appendingPathComponent("DownloadedModels", isDirectory: true),
                                       bundleRoot: Bundle.main.resourceURL)
        return ModelLibrary(catalog: catalog, storage: storage)
    }

    /// Every first-use caller joins the same restoration of the saved selection.
    func prepare() async {
        if isInitialized { return }
        if let preparation { await preparation.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            self.isInitialized = true
        }
        preparation = task
        await task.value
        preparation = nil
    }

    func refresh() async {
        isRefreshing = true
        inventory = await storage.inventory()
        selectedID = await storage.selectedModelID()
        ownedIDs = await storage.ownedModelIDs()
        for id in ownedIDs where !installed(id) && downloads[id] == nil {
            if await storage.hasFinalDirectory(id) {
                downloads[id] = .failed("This copy is incomplete or damaged. Remove it, then download again.")
            } else {
                downloads[id] = .paused(resumable: await storage.completedBytes(id) > 0)
            }
        }
        availableDiskBytes = await storage.availableDiskBytes()
        isRefreshing = false
    }

    func descriptor(for id: String) -> ModelDescriptor? { catalog.model(id: id) }
    func installed(_ id: String) -> Bool { inventory.contains { $0.id == id } }
    func removable(_ id: String) -> Bool {
        descriptor(for: id)?.isBundled == false && ownedIDs.contains(id) &&
            !protectedIDs.contains(id) && tasks[id] == nil
    }

    func download(_ id: String) {
        guard tasks[id] == nil, !installed(id) else { return }
        guard let descriptor = descriptor(for: id), !descriptor.isBundled else {
            error = "This model cannot be downloaded from the catalog."; return
        }
        error = nil
        downloads[id] = .progress(received: 0, total: descriptor.totalBytes)
        tasks[id] = Task { [weak self] in
            guard let self else { throw CancellationError() }
            defer { self.tasks.removeValue(forKey: id) }
            do {
                _ = try await self.downloader.download(descriptor) { [weak self] state in
                    await self?.receive(state, for: id)
                }
                self.downloads[id] = .ready
                await self.refresh()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    self.downloads[id] = .paused(resumable: await self.storage.completedBytes(id) > 0)
                    await self.refresh()
                    throw CancellationError()
                }
                self.downloads[id] = .failed(error.localizedDescription)
                await self.refresh()
                throw error
            }
        }
    }

    func cancelDownload(_ id: String) { tasks[id]?.cancel() }

    /// Also used by device smoke checks. Cancelling this waiter cancels and joins
    /// the real transfer, so no hidden download continues after a timeout.
    func awaitDownload(_ id: String) async throws {
        await prepare()
        guard let descriptor = descriptor(for: id) else {
            throw ModelStorageError.unavailable("This model is not in the catalog.")
        }
        if installed(id) { return }
        download(id)
        guard let task = tasks[id] else {
            throw ModelStorageError.unavailable("This model cannot be downloaded.")
        }
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: { task.cancel() }
    }

    func remove(_ id: String) async throws {
        guard tasks[id] == nil else { throw ModelStorageError.transferInProgress }
        try await storage.delete(id)
        downloads.removeValue(forKey: id)
        await refresh()
    }

    func directory(for id: String) async throws -> URL {
        await prepare()
        return try await storage.directory(for: id)
    }
    func commitSelection(_ id: String) async throws {
        try await storage.commitSelection(id)
        selectedID = id
    }
    func protect(_ id: String) async throws {
        try await storage.protect(id)
        protectedIDs.insert(id)
    }
    func unprotect(_ id: String) async {
        await storage.unprotect(id)
        protectedIDs.remove(id)
    }

    private func receive(_ state: ModelDownloadState, for id: String) {
        guard tasks[id] != nil else { return }
        if case .progress(let received, let total) = state {
            // Delegate delivery can trail verification; progress must never move
            // backwards or make an already verified model look unfinished.
            guard case .progress(let previous, _) = downloads[id] else { return }
            downloads[id] = .progress(received: max(previous, received), total: total)
        } else { downloads[id] = state }
    }
}
