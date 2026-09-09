import CryptoKit
import Foundation
import XCTest
@testable import CampingCore

@MainActor
final class ModelManagementTests: XCTestCase {
    func testShippedCatalogPinsEveryArtifactAndHasSelectableDefault() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try ModelCatalog(data: Data(contentsOf: project.appendingPathComponent("Resources/ModelCatalog/catalog.json")))
        // The app ships exactly one model. Changing that is an editorial
        // decision, not an accident, so it has to be made here too.
        XCTAssertEqual(catalog.models.map(\.id), ["bonsai-27b-1bit"])
        XCTAssertEqual(catalog.defaultModelID, "bonsai-27b-1bit")
        let shipped = try XCTUnwrap(catalog.model(id: catalog.defaultModelID))
        XCTAssertFalse(shipped.isBundled, "No weights ship inside the app bundle.")
        XCTAssertEqual(shipped.quantizationBits, 1)
        XCTAssertEqual(shipped.repository, "prism-ml/Bonsai-27B-mlx-1bit")
        XCTAssertFalse(shipped.files.isEmpty)
        for model in catalog.models {
            XCTAssertEqual(model.files.reduce(Int64(0)) { $0 + $1.size }, model.totalBytes)
            for file in model.files { XCTAssertEqual(try model.downloadURL(for: file).host, "huggingface.co") }
        }
    }

    func testCatalogRejectsTraversalMutableRevisionAndIncorrectTotal() throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let valid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.catalog)) as! [String: Any]
        for (key, value) in [("revision", "main" as Any), ("totalBytes", 7 as Any),
                             ("repository", "unknown-community/model" as Any), ("id", "../outside" as Any),
                             ("validationStatus", "untested-but-approved" as Any)] {
            var object = valid
            var models = object["models"] as! [[String: Any]]
            models[1][key] = value; object["models"] = models
            XCTAssertThrowsError(try ModelCatalog(data: JSONSerialization.data(withJSONObject: object)), key)
        }
        for path in ["../model.safetensors", "/tmp/config.json", "a//b", "a/./b", "a/%2e%2e/b", "a\\b", ".hidden"] {
            XCTAssertFalse(ModelCatalog.safeRelativePath(path), path)
        }
        var object = valid
        var models = object["models"] as! [[String: Any]]
        var files = models[1]["files"] as! [[String: Any]]
        files[0]["path"] = "../config.json"; models[1]["files"] = files; object["models"] = models
        XCTAssertThrowsError(try ModelCatalog(data: JSONSerialization.data(withJSONObject: object)))
    }

    func testDownloadTrustRejectsCredentialsInsecureURLsHostLookalikesAndHTTPFailures() throws {
        for string in ["http://huggingface.co/a", "https://huggingface.co.evil.example/a",
                       "https://evil.example/huggingface.co/a", "https://user:password@huggingface.co/a",
                       "https://us.aws.cdn.hf.co.evil.example/a", "https://arbitrary.hf.co/a",
                       "https://attacker.us.aws.cdn.hf.co/a", "http://us.aws.cdn.hf.co/a",
                       "https://huggingface.co:8443/a", "file:///tmp/model"] {
            XCTAssertThrowsError(try ModelDownloadTrust.validate(URL(string: string)!))
        }
        let url = URL(string: "https://huggingface.co/mlx-community/model/resolve/commit/config.json")!
        for status in [206, 302, 401, 403, 404, 429, 500] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            XCTAssertThrowsError(try ModelDownloadTrust.validateResponse(response))
        }
        for string in ["https://huggingface.co/a", "https://cdn-lfs.huggingface.co/a",
                       "https://cas-bridge.xethub.hf.co/a", "https://us.aws.cdn.hf.co/a"] {
            XCTAssertNoThrow(try ModelDownloadTrust.validate(URL(string: string)!))
        }
    }

    func testInterruptedDownloadReusesOnlyVerifiedCompletedFilesAndCleansCrashPart() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let storage = try fixture.storage()
        let transport = FixtureTransport(payloads: fixture.payloads, failOnce: "tokenizer.json")
        let downloader = ModelDownloader(storage: storage, transport: transport)
        do {
            _ = try await downloader.download(fixture.downloaded) { _ in }
            XCTFail("The simulated network interruption should fail")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let initialInventory = await storage.inventory()
        XCTAssertEqual(initialInventory.map(\.id), [fixture.bundled.id])
        let stage = fixture.downloadRoot.appendingPathComponent(".staging/\(fixture.downloaded.id)")
        let abandoned = stage.appendingPathComponent("transfer-\(UUID().uuidString)")
        try Data(repeating: 1, count: 32).write(to: abandoned)
        _ = try await downloader.download(fixture.downloaded) { _ in }
        let counts = await transport.counts
        XCTAssertEqual(counts["config.json"], 1, "The already verified configuration should be reused")
        XCTAssertEqual(counts["tokenizer.json"], 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        let finalInventory = await storage.inventory()
        XCTAssertEqual(Set(finalInventory.map(\.id)), [fixture.bundled.id, fixture.downloaded.id])
    }

    func testCancellationRemovesCurrentPartialAndNeverPublishesReady() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let storage = try fixture.storage()
        let transport = FixtureTransport(payloads: fixture.payloads, block: "model.safetensors")
        let downloader = ModelDownloader(storage: storage, transport: transport)
        let task = Task { try await downloader.download(fixture.downloaded) { _ in } }
        await transport.waitForRequest("model.safetensors")
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transfer must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        let inventory = await storage.inventory()
        XCTAssertFalse(inventory.contains { $0.id == fixture.downloaded.id })
        let stage = fixture.downloadRoot.appendingPathComponent(".staging/\(fixture.downloaded.id)")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: stage.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix("transfer-") })
        XCTAssertFalse(remaining.contains(".camping-ready.json"))
        XCTAssertTrue(remaining.contains("config.json"), "Completed verified files remain resumable")
        await transport.unblock()
        _ = try await downloader.download(fixture.downloaded) { _ in }
        let counts = await transport.counts
        XCTAssertEqual(counts["config.json"], 1)
        XCTAssertEqual(counts["model.safetensors"], 2)
    }

    func testCorruptedTransferFailsChecksumAndRetryCanRecover() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let storage = try fixture.storage()
        let transport = FixtureTransport(payloads: fixture.payloads, corruptOnce: "model.safetensors")
        let downloader = ModelDownloader(storage: storage, transport: transport)
        do { _ = try await downloader.download(fixture.downloaded) { _ in }; XCTFail("Corruption must fail") }
        catch { XCTAssertEqual(error as? ModelStorageError, .invalidFile("model.safetensors")) }
        let before = await storage.inventory()
        XCTAssertFalse(before.contains { $0.id == fixture.downloaded.id })
        _ = try await downloader.download(fixture.downloaded) { _ in }
        let directory = try await storage.directory(for: fixture.downloaded.id)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")), fixture.payloads["model.safetensors"])
    }

    func testSelectionSurvivesRestartAndEditorialCatalogChangesWithoutRedownload() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let storage = try fixture.storage()
        _ = try await ModelDownloader(storage: storage, transport: FixtureTransport(payloads: fixture.payloads))
            .download(fixture.downloaded) { _ in }
        try await storage.commitSelection(fixture.downloaded.id)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.catalog)) as! [String: Any]
        var models = object["models"] as! [[String: Any]]
        models[1]["validationStatus"] = "device-smoke-tested"
        models[1]["name"] = "A clearer name"
        models[1]["provenance"] = "Updated attribution details"
        object["models"] = models
        let edited = try ModelCatalog(data: JSONSerialization.data(withJSONObject: object))
        let restarted = try fixture.storage(catalog: edited)
        let selected = await restarted.selectedModelID()
        XCTAssertEqual(selected, fixture.downloaded.id)
        _ = try await restarted.directory(for: selected)
        try await restarted.protect(fixture.downloaded.id)
        do { try await restarted.delete(fixture.downloaded.id); XCTFail("In-use files must remain protected") }
        catch { XCTAssertEqual(error as? ModelStorageError, .protectedModel) }
        await restarted.unprotect(fixture.downloaded.id)
        // The selection may be removed to reclaim space; it simply is not installed afterwards.
        try await restarted.delete(fixture.downloaded.id)
        let remaining = await restarted.inventory()
        XCTAssertFalse(remaining.contains { $0.id == fixture.downloaded.id })
        do { try await restarted.delete(fixture.bundled.id); XCTFail("The baseline is not removable") }
        catch { XCTAssertEqual(error as? ModelStorageError, .protectedModel) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
    }

    func testDamagedInstalledCopyIsRejectedBeforeLoadAndCanBeRemovedSafely() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let storage = try fixture.storage()
        let installed = try await ModelDownloader(storage: storage, transport: FixtureTransport(payloads: fixture.payloads))
            .download(fixture.downloaded) { _ in }
        let weight = installed.directory.appendingPathComponent("model.safetensors")
        let data = fixture.payloads["model.safetensors"]!
        try Data(repeating: 255, count: data.count).write(to: weight, options: .atomic)
        let restarted = try fixture.storage()
        do { _ = try await restarted.directory(for: fixture.downloaded.id); XCTFail("Same-size corruption must be detected") }
        catch { XCTAssertEqual(error as? ModelStorageError, .invalidFile("model.safetensors")) }
        // A size failure also removes the copy from fast inventory but must not
        // make its owned files impossible to delete from the model manager.
        try Data([0]).write(to: weight)
        let inventory = await restarted.inventory()
        XCTAssertFalse(inventory.contains { $0.id == fixture.downloaded.id })
        let owned = await restarted.ownedModelIDs()
        XCTAssertTrue(owned.contains(fixture.downloaded.id))
        try await restarted.delete(fixture.downloaded.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.bundleDirectory.path))
    }

    func testInsufficientDiskAndSymlinkEscapeFailBeforeFetching() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let transport = FixtureTransport(payloads: fixture.payloads)
        let storage = try fixture.storage(capacity: { _ in 0 })
        do {
            _ = try await ModelDownloader(storage: storage, transport: transport).download(fixture.downloaded) { _ in }
            XCTFail("Disk preflight must fail")
        } catch { XCTAssertEqual(error as? ModelStorageError, .insufficientSpace) }
        let counts = await transport.counts
        XCTAssertTrue(counts.isEmpty)
        let otherStorage = try fixture.storage()
        let stage = fixture.downloadRoot.appendingPathComponent(".staging/\(fixture.downloaded.id)")
        let external = fixture.root.appendingPathComponent("external-config.json")
        try fixture.payloads["config.json"]!.write(to: external)
        try FileManager.default.createSymbolicLink(at: stage.appendingPathComponent("config.json"), withDestinationURL: external)
        do {
            _ = try await ModelDownloader(storage: otherStorage, transport: transport).download(fixture.downloaded) { _ in }
            XCTFail("Symlink must fail without touching the external file")
        } catch { XCTAssertTrue(error is ModelStorageError) }
        XCTAssertEqual(try Data(contentsOf: external), fixture.payloads["config.json"])
    }

    func testGitBlobDigestVerifiesContentWithItsLengthPrefix() throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        let data = Data("small trusted metadata\n".utf8)
        let path = fixture.root.appendingPathComponent("metadata.txt")
        try data.write(to: path)
        var digest = Insecure.SHA1(); digest.update(data: Data("blob \(data.count)\0".utf8)); digest.update(data: data)
        let file = ModelFile(path: "metadata.txt", size: Int64(data.count), gitBlobSHA: ModelFileVerifier.hex(digest.finalize()))
        XCTAssertNoThrow(try ModelFileVerifier.verify(path, file: file))
        let raw = ModelFile(path: "metadata.txt", size: Int64(data.count), gitBlobSHA: ModelFileVerifier.hex(Insecure.SHA1.hash(data: data)))
        XCTAssertThrowsError(try ModelFileVerifier.verify(path, file: raw))
    }

    func testOnlyOneTransferCanReserveDiskAndCancelledReservationIsReleased() async throws {
        let fixture = try ModelFixture(); defer { fixture.clean() }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.catalog)) as! [String: Any]
        var models = object["models"] as! [[String: Any]]
        var additional = models[1]; additional["id"] = "second-model"
        models.append(additional); object["models"] = models
        let catalog = try ModelCatalog(data: JSONSerialization.data(withJSONObject: object))
        let storage = try fixture.storage(catalog: catalog)
        _ = try await storage.beginDownload(fixture.downloaded.id)
        do { _ = try await storage.beginDownload("second-model"); XCTFail("Simultaneous reservations must fail") }
        catch { XCTAssertEqual(error as? ModelStorageError, .transferInProgress) }
        await storage.endDownload(fixture.downloaded.id)
        _ = try await storage.beginDownload("second-model")
        await storage.endDownload("second-model")
    }
}

private struct ModelFixture {
    let root: URL
    let downloadRoot: URL
    let bundleRoot: URL
    let bundleDirectory: URL
    let payloads: [String: Data]
    let bundled: ModelDescriptor
    let downloaded: ModelDescriptor
    let catalog: ModelCatalog

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("CampingModels-\(UUID().uuidString)")
        downloadRoot = root.appendingPathComponent("downloads")
        bundleRoot = root.appendingPathComponent("bundle")
        bundleDirectory = bundleRoot.appendingPathComponent("Models/baseline")
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        // Tiny real safetensors structure: one F32 tensor containing zero.
        let header = Data(#"{"weight":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}"#.utf8)
        var length = UInt64(header.count).littleEndian
        var weights = withUnsafeBytes(of: &length) { Data($0) }
        weights.append(header); weights.append(Data(repeating: 0, count: 4))
        let content = [
            "config.json": Data(#"{"model_type":"qwen2","quantization":{"bits":4,"group_size":64}}"#.utf8),
            "tokenizer.json": Data(#"{"model":{"type":"BPE","vocab":{},"merges":[]}}"#.utf8),
            "tokenizer_config.json": Data(#"{"chat_template":"{{ messages }}"}"#.utf8),
            "model.safetensors": weights
        ]
        payloads = content
        let order = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]
        let files = order.map { path in
            let data = content[path]!
            return ModelFile(path: path, size: Int64(data.count), sha256: ModelFileVerifier.hex(SHA256.hash(data: data)))
        }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        func descriptor(_ id: String, bundledPath: String? = nil) -> ModelDescriptor {
            ModelDescriptor(id: id, name: id, family: "Qwen", repository: "mlx-community/fixture",
                            revision: String(repeating: "a", count: 40), totalBytes: total, files: files,
                            license: "Apache-2.0", provenance: "Local test fixture", bundledRelativePath: bundledPath,
                            modelType: "qwen2", quantizationBits: 4, compatibilityNote: "Fixture only")
        }
        bundled = descriptor("baseline", bundledPath: "Models/baseline")
        downloaded = descriptor("small-model")
        catalog = try ModelCatalog(defaultModelID: bundled.id, models: [bundled, downloaded])
        for (path, data) in payloads { try data.write(to: bundleDirectory.appendingPathComponent(path)) }
    }

    func storage(catalog replacement: ModelCatalog? = nil,
                 capacity: (@Sendable (URL) -> Int64?)? = { _ in 100_000_000_000 }) throws -> ModelStorage {
        try ModelStorage(catalog: replacement ?? catalog, rootDirectory: downloadRoot,
                         bundleRoot: bundleRoot, capacityProvider: capacity)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private actor FixtureTransport: ModelFileTransport {
    let payloads: [String: Data]
    var failOnce: String?
    var corruptOnce: String?
    var block: String?
    var counts: [String: Int] = [:]
    var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    init(payloads: [String: Data], failOnce: String? = nil, corruptOnce: String? = nil, block: String? = nil) {
        self.payloads = payloads; self.failOnce = failOnce; self.corruptOnce = corruptOnce; self.block = block
    }
    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let path = url.lastPathComponent
        counts[path, default: 0] += 1
        if failOnce == path { failOnce = nil; throw URLError(.networkConnectionLost) }
        var data = payloads[path]!
        if corruptOnce == path { corruptOnce = nil; data = Data(repeating: 255, count: data.count) }
        if block == path {
            try data.prefix(data.count / 2).write(to: destination)
            progress(Int64(data.count / 2))
            waiters.removeValue(forKey: path)?.resume()
            try await Task.sleep(for: .seconds(30))
        }
        waiters.removeValue(forKey: path)?.resume()
        try Task.checkCancellation()
        try data.write(to: destination)
        progress(Int64(data.count))
    }
    func waitForRequest(_ path: String) async {
        if counts[path] != nil { return }
        await withCheckedContinuation { waiters[path] = $0 }
    }
    func unblock() { block = nil }
}
