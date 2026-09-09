import CryptoKit
import Foundation

public enum ModelStorageError: Error, LocalizedError, Equatable {
    case unavailable(String), invalidFile(String), protectedModel, transferInProgress, insufficientSpace
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .invalidFile(let path): "The model file failed verification: \(path). Retry the download."
        case .protectedModel: "Switch to another model before removing this one. Bundled and system-managed models cannot be removed."
        case .transferInProgress: "Wait for the current model download to finish or stop before starting another."
        case .insufficientSpace: "There is not enough free space for this model and a small storage reserve."
        }
    }
}

public struct InstalledModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let directory: URL
    public let isBundled: Bool
    public let totalBytes: Int64
}

public enum ModelFileVerifier {
    /// Hashes fixed-size chunks; the model is never materialized as a giant Data.
    public static func verify(_ url: URL, file: ModelFile) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == file.size else { throw ModelStorageError.invalidFile(file.path) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let expected = file.sha256 {
            var digest = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation(); digest.update(data: chunk)
            }
            guard hex(digest.finalize()) == expected else { throw ModelStorageError.invalidFile(file.path) }
        } else if let expected = file.gitBlobSHA {
            var digest = Insecure.SHA1()
            digest.update(data: Data("blob \(file.size)\0".utf8))
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation(); digest.update(data: chunk)
            }
            guard hex(digest.finalize()) == expected else { throw ModelStorageError.invalidFile(file.path) }
        } else { throw ModelStorageError.invalidFile(file.path) }
        try Task.checkCancellation()
    }
    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public actor ModelStorage {
    public let catalog: ModelCatalog
    public let rootDirectory: URL
    public let bundleRoot: URL?
    private var protectedIDs = Set<String>()
    private var transferringIDs = Set<String>()
    private var verifiedSignatures: [String: [FileSignature]] = [:]
    private var selectedID: String
    private let capacityProvider: (@Sendable (URL) -> Int64?)?
    private struct Selection: Codable { let selectedID: String }
    private struct ReadyMarker: Codable { let fingerprint: String }
    private struct FileSignature: Equatable {
        let size: Int
        let modified: Date?
    }
    private struct ArtifactIdentity: Encodable {
        let id: String
        let repository: String
        let revision: String
        let files: [ModelFile]
        let modelType: String
        let textModelType: String?
        let quantizationBits: Int
        let runtime: ModelRuntime?
    }

    public init(catalog: ModelCatalog, rootDirectory: URL, bundleRoot: URL?,
                capacityProvider: (@Sendable (URL) -> Int64?)? = nil) throws {
        try catalog.validate()
        self.catalog = catalog
        self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.bundleRoot = bundleRoot?.standardizedFileURL.resolvingSymlinksInPath()
        self.capacityProvider = capacityProvider
        try FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        var excludedURL = self.rootDirectory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excludedURL.setResourceValues(values)
        let selectionURL = self.rootDirectory.appendingPathComponent("selection.json")
        if selectionURL.resolvingSymlinksInPath().path == selectionURL.path,
           let data = try? Data(contentsOf: selectionURL),
           let saved = try? JSONDecoder().decode(Selection.self, from: data),
           catalog.model(id: saved.selectedID) != nil {
            selectedID = saved.selectedID
        } else { selectedID = catalog.defaultModelID }
    }

    public func inventory() -> [InstalledModel] {
        catalog.models.compactMap { model in
            guard let directory = try? installedDirectory(model) else { return nil }
            return InstalledModel(id: model.id, directory: directory,
                                  isBundled: model.isBundled, totalBytes: model.totalBytes)
        }
    }

    public func selectedModelID() -> String {
        if let model = catalog.model(id: selectedID),
           (try? installedDirectory(model)) != nil { return selectedID }
        selectedID = catalog.defaultModelID
        return selectedID
    }

    public func directory(for id: String) throws -> URL {
        let model = try descriptor(id)
        let directory = try installedDirectory(model)
        // Bundled assets are verified during provisioning and protected by the
        // signed app bundle. Downloaded assets are hashed before first use and
        // again if their on-disk metadata changes in this session.
        if !model.isBundled {
            let signatures = try fileSignatures(model, directory: directory)
            if verifiedSignatures[id] != signatures {
                for file in model.files {
                    try ModelFileVerifier.verify(safeURL(directory, file.path), file: file)
                }
                verifiedSignatures[id] = signatures
            }
        }
        return directory
    }

    /// Includes interrupted and damaged copies, so they can still be removed.
    public func ownedModelIDs() -> Set<String> {
        Set(catalog.models.filter { model in
            !model.isBundled && [model.id, ".staging/\(model.id)"].contains { path in
                guard let url = try? safeURL(rootDirectory, path) else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
        }.map(\.id))
    }

    public func hasFinalDirectory(_ id: String) -> Bool {
        guard let model = catalog.model(id: id), !model.isBundled,
              let url = try? safeURL(rootDirectory, id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func commitSelection(_ id: String) throws {
        _ = try descriptor(id)
        _ = try directory(for: id)
        let data = try JSONEncoder().encode(Selection(selectedID: id))
        try data.write(to: safeURL(rootDirectory, "selection.json"), options: .atomic)
        selectedID = id
    }

    public func protect(_ id: String) throws {
        _ = try descriptor(id)
        _ = try directory(for: id)
        protectedIDs.insert(id)
    }
    public func unprotect(_ id: String) { protectedIDs.remove(id) }

    public func delete(_ id: String) throws {
        let model = try descriptor(id)
        guard !model.isBundled, !protectedIDs.contains(id) else { throw ModelStorageError.protectedModel }
        guard !transferringIDs.contains(id) else { throw ModelStorageError.transferInProgress }
        // Exactly these catalog-owned locations; no arbitrary paths or recursion
        // into other models, the app bundle, or the user's external model folder.
        for path in [id, ".staging/\(id)"] {
            let url = try safeURL(rootDirectory, path)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        verifiedSignatures.removeValue(forKey: id)
    }

    public func availableDiskBytes() -> Int64? {
        if let capacityProvider { return capacityProvider(rootDirectory) }
        if let values = try? rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage { return bytes }
        return (try? FileManager.default.attributesOfFileSystem(forPath: rootDirectory.path)[.systemFreeSize] as? NSNumber)?.int64Value
    }

    public func beginDownload(_ id: String) throws -> URL {
        let model = try descriptor(id)
        guard !model.isBundled else { throw ModelStorageError.protectedModel }
        guard transferringIDs.isEmpty else { throw ModelStorageError.transferInProgress }
        let final = try safeURL(rootDirectory, id)
        guard !FileManager.default.fileExists(atPath: final.path) else {
            throw ModelStorageError.unavailable("This model already has files on the device. Remove the unused copy before retrying.")
        }
        let stage = try safeURL(rootDirectory, ".staging/\(id)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        // A terminated process cannot clean its current URLSession temporary
        // file. Remove only our named, inactive transfer files for this ID.
        for item in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let name = item.lastPathComponent
            if name.hasPrefix("transfer-"), UUID(uuidString: String(name.dropFirst(9))) != nil {
                try FileManager.default.removeItem(at: safeURL(stage, name))
            }
        }
        let completed = completedBytes(id)
        if let free = availableDiskBytes(), free < model.totalBytes - completed + 256 * 1024 * 1024 {
            throw ModelStorageError.insufficientSpace
        }
        transferringIDs.insert(id)
        return stage
    }
    public func endDownload(_ id: String) { transferringIDs.remove(id) }

    public func verifiedStagedFile(_ file: ModelFile, modelID: String) throws -> Bool {
        let model = try descriptor(modelID)
        guard model.files.contains(file) else { throw ModelStorageError.invalidFile(file.path) }
        let url = try safeURL(rootDirectory, ".staging/\(modelID)/\(file.path)")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do { try ModelFileVerifier.verify(url, file: file); return true }
        catch is CancellationError { throw CancellationError() }
        catch {
            // A corrupt completed file cannot be reused; replace only this
            // catalog-owned staged file on the next transfer.
            try FileManager.default.removeItem(at: url)
            return false
        }
    }

    public func acceptDownloadedFile(_ temporary: URL, file: ModelFile, modelID: String) throws {
        guard transferringIDs.contains(modelID), try descriptor(modelID).files.contains(file) else {
            throw ModelStorageError.transferInProgress
        }
        let stage = try safeURL(rootDirectory, ".staging/\(modelID)")
        guard temporary.deletingLastPathComponent().standardizedFileURL == stage,
              temporary.lastPathComponent.hasPrefix("transfer-") else {
            throw ModelStorageError.invalidFile(file.path)
        }
        try ModelFileVerifier.verify(temporary, file: file)
        let target = try safeURL(stage, file.path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    public func completedBytes(_ id: String) -> Int64 {
        guard let model = catalog.model(id: id) else { return 0 }
        return model.files.reduce(0) { total, file in
            guard let url = try? safeURL(rootDirectory, ".staging/\(id)/\(file.path)"),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Int64(size) == file.size else { return total }
            return total + file.size
        }
    }

    public func finishDownload(_ id: String) throws -> InstalledModel {
        let model = try descriptor(id)
        guard transferringIDs.contains(id) else { throw ModelStorageError.transferInProgress }
        let stage = try safeURL(rootDirectory, ".staging/\(id)")
        for file in model.files {
            try Task.checkCancellation()
            try ModelFileVerifier.verify(safeURL(stage, file.path), file: file)
        }
        try verifyStructure(model, directory: stage)
        let marker = ReadyMarker(fingerprint: try fingerprint(model))
        try JSONEncoder().encode(marker).write(to: safeURL(stage, ".camping-ready.json"), options: .atomic)
        try Task.checkCancellation()
        let destination = try safeURL(rootDirectory, id)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ModelStorageError.transferInProgress }
        let signatures = try fileSignatures(model, directory: stage)
        try FileManager.default.moveItem(at: stage, to: destination)
        verifiedSignatures[id] = signatures
        return InstalledModel(id: id, directory: destination, isBundled: false, totalBytes: model.totalBytes)
    }

    private func descriptor(_ id: String) throws -> ModelDescriptor {
        guard let model = catalog.model(id: id) else { throw ModelStorageError.unavailable("This model is not in the catalog.") }
        return model
    }

    private func installedDirectory(_ model: ModelDescriptor) throws -> URL {
        let directory: URL
        if let path = model.bundledRelativePath, let bundleRoot {
            directory = try safeURL(bundleRoot, path)
        } else if !model.isBundled {
            directory = try safeURL(rootDirectory, model.id)
            let marker = try JSONDecoder().decode(ReadyMarker.self,
                from: Data(contentsOf: safeURL(directory, ".camping-ready.json")))
            guard marker.fingerprint == (try fingerprint(model)) else { throw ModelStorageError.invalidFile(model.id) }
        } else { throw ModelStorageError.unavailable("The bundled model is missing from this build.") }
        for file in model.files {
            let path = try safeURL(directory, file.path)
            let values = try path.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == file.size else {
                throw ModelStorageError.invalidFile(file.path)
            }
        }
        try verifyStructure(model, directory: directory)
        return directory
    }

    private func verifyStructure(_ model: ModelDescriptor, directory: URL) throws {
        let config = try jsonObject(safeURL(directory, "config.json"))
        let tokenizer = try jsonObject(safeURL(directory, "tokenizer_config.json"))
        guard config["model_type"] as? String == model.modelType else { throw ModelStorageError.invalidFile("config.json architecture") }
        if let textType = model.textModelType {
            guard (config["text_config"] as? [String: Any])?["model_type"] as? String == textType else {
                throw ModelStorageError.invalidFile("config.json text architecture")
            }
        }
        let quantization = (config["quantization"] ?? config["quantization_config"]) as? [String: Any]
        guard (quantization?["bits"] as? NSNumber)?.intValue == model.quantizationBits else {
            throw ModelStorageError.invalidFile("config.json quantization")
        }
        let hasInlineTemplate = (tokenizer["chat_template"] as? String)?.isEmpty == false || tokenizer["chat_template"] is [[String: Any]]
        let external = try safeURL(directory, "chat_template.jinja")
        let hasExternalTemplate = model.files.contains { $0.path == "chat_template.jinja" } &&
            (try? String(contentsOf: external, encoding: .utf8).isEmpty) == false
        guard hasInlineTemplate || hasExternalTemplate else { throw ModelStorageError.invalidFile("local chat template") }
        if model.files.contains(where: { $0.path == "model.safetensors.index.json" }) {
            let index = try jsonObject(safeURL(directory, "model.safetensors.index.json"))
            guard let mapping = index["weight_map"] as? [String: String], !mapping.isEmpty else {
                throw ModelStorageError.invalidFile("model.safetensors.index.json")
            }
            let shards = Set(model.files.filter { $0.path.hasSuffix(".safetensors") }.map(\.path))
            guard Set(mapping.values).isSubset(of: shards) else { throw ModelStorageError.invalidFile("missing model shard") }
        }
    }

    private func jsonObject(_ url: URL) throws -> [String: Any] {
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw ModelStorageError.invalidFile(url.lastPathComponent)
        }
        return object
    }
    private func fingerprint(_ model: ModelDescriptor) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let identity = ArtifactIdentity(id: model.id, repository: model.repository, revision: model.revision,
                                        files: model.files.sorted { $0.path < $1.path }, modelType: model.modelType,
                                        textModelType: model.textModelType, quantizationBits: model.quantizationBits,
                                        runtime: model.backend == .mlx ? nil : model.backend)
        return ModelFileVerifier.hex(SHA256.hash(data: try encoder.encode(identity)))
    }
    private func fileSignatures(_ model: ModelDescriptor, directory: URL) throws -> [FileSignature] {
        try model.files.map { file in
            let values = try safeURL(directory, file.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileSignature(size: values.fileSize ?? -1, modified: values.contentModificationDate)
        }
    }
    private func safeURL(_ root: URL, _ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"), resolved.path == url.path else {
            throw ModelStorageError.unavailable("A model path is unsafe or contains a symbolic link.")
        }
        return url
    }
}
