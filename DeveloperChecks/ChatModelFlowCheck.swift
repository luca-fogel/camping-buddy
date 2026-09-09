import Foundation

// Deterministic coordinator checks only. These doubles never load weights or
// perform inference, and their text must never be presented as device evidence.
struct LocalGeneration: Sendable {
    let text: String
    let metrics: String
    let modelID: String
    let modelName: String
}

actor EngineProbe {
    static let shared = EngineProbe()
    private var failingModels = Set<String>()
    private var events: [String] = []
    func fail(_ ids: Set<String>) { failingModels = ids }
    func shouldFail(_ id: String) -> Bool { failingModels.contains(id) }
    func record(_ event: String) { events.append(event) }
    func resetEvents() { events.removeAll() }
    func recordedEvents() -> [String] { events }
}

actor CampingModelEngine {
    private var loaded: ModelDescriptor?
    private var working = false
    func load(directory: URL?, model: ModelDescriptor) async throws -> Double {
        precondition(!working && loaded == nil, "Replacement allocated while previous model was retained")
        working = true
        defer { working = false }
        await EngineProbe.shared.record("load-start:\(model.id)")
        try await Task.sleep(for: .milliseconds(100))
        if await EngineProbe.shared.shouldFail(model.id) { throw CocoaError(.fileReadCorruptFile) }
        loaded = model
        await EngineProbe.shared.record("load-ready:\(model.id)")
        return 0.1
    }
    func unload() async throws {
        precondition(!working, "Unloaded before active computation finished")
        await EngineProbe.shared.record("unload:\(loaded?.id ?? "none")")
        loaded = nil
    }
    func answer(prompt: String) async throws -> LocalGeneration {
        precondition(!working)
        guard let loaded else { throw CocoaError(.fileReadUnknown) }
        working = true
        defer { working = false }
        await EngineProbe.shared.record("generation-start:\(loaded.id)")
        do { try await Task.sleep(for: .milliseconds(120)) }
        catch {
            // Model work can continue briefly after consumer cancellation.
            let drain = Task { try? await Task.sleep(for: .milliseconds(70)) }
            await drain.value
            await EngineProbe.shared.record("generation-drained:\(loaded.id)")
            throw CancellationError()
        }
        await EngineProbe.shared.record("generation-finished:\(loaded.id)")
        return LocalGeneration(text: "Pack a sleeping pad. [sleep-gear]",
                               metrics: "Controlled coordinator test only: \(loaded.id)",
                               modelID: loaded.id, modelName: loaded.name)
    }
}

@MainActor
final class ModelLibrary {
    let catalog: ModelCatalog
    var selectedID: String
    var protectedIDs = Set<String>()
    var failCommit = false
    var initializationCount = 0
    private var initialized = false
    init(catalog: ModelCatalog, selectedID: String? = nil) {
        self.catalog = catalog
        self.selectedID = selectedID ?? catalog.defaultModelID
    }
    func prepare() async {
        if initialized { return }
        initialized = true
        initializationCount += 1
    }
    func descriptor(for id: String) -> ModelDescriptor? { catalog.model(id: id) }
    func directory(for id: String) async throws -> URL {
        guard descriptor(for: id) != nil else { throw CocoaError(.fileNoSuchFile) }
        return URL(fileURLWithPath: "/virtual-coordinator-test/\(id)")
    }
    func protect(_ id: String) async throws { protectedIDs.insert(id) }
    func unprotect(_ id: String) async { protectedIDs.remove(id) }
    func commitSelection(_ id: String) async throws {
        if failCommit { throw CocoaError(.fileWriteNoPermission) }
        selectedID = id
    }
}

@main
struct ChatModelFlowCheck {
    @MainActor static func main() async throws {
        let passage = ReferencePassage(
            id: "sleep-gear", title: "Sleeping gear", text: "Pack a sleeping pad.",
            keywords: ["sleep", "gear", "pack"], sourceTitle: "Controlled test reference",
            sourceURL: "https://example.com/reference", accessedDate: "2026-09-05",
            region: "Test", rights: "Original test data", reviewStatus: "Test only")
        let references = try ReferenceLibrary(data: JSONEncoder().encode([passage]))
        let files = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"].map {
            ModelFile(path: $0, size: 1, sha256: String(repeating: "0", count: 64))
        }
        func descriptor(_ id: String, bundled: Bool = false) -> ModelDescriptor {
            ModelDescriptor(id: id, name: "Test \(id)", family: "test",
                            repository: "mlx-community/controlled-test", revision: String(repeating: "0", count: 40),
                            totalBytes: 4, files: files, license: "Test", provenance: "Controlled test data",
                            bundledRelativePath: bundled ? "Models/test" : nil, modelType: "test",
                            quantizationBits: 4, compatibilityNote: "No weights, no inference")
        }
        let catalog = try ModelCatalog(defaultModelID: "old", models: [descriptor("old", bundled: true), descriptor("new")])
        func makeModel(selectedID: String? = nil) -> ChatModel {
            let model = ChatModel(modelLibrary: ModelLibrary(catalog: catalog, selectedID: selectedID))
            model.library = references
            model.libraryError = nil
            return model
        }
        let question = "What sleeping gear should I pack?"
        func ask(_ model: ChatModel) { model.draft = question; model.sendWithPreparation() }

        let first = makeModel(selectedID: "new")
        ask(first)
        first.draft = "An edited draft"
        precondition(!first.clearConversation())
        try await settle(first)
        precondition(first.activeDescriptor?.id == "new" && first.entries.count == 1)
        precondition(first.entries[0].isGenerated && first.entries[0].modelID == "new")
        precondition(first.entries[0].metrics?.contains("new") == true && first.draft == "An edited draft")
        precondition(first.modelLibrary.initializationCount == 1)
        ask(first)
        try await Task.sleep(for: .milliseconds(20))
        await first.stopAndWait()
        precondition(!first.isBusy && first.isReady && first.entries.last?.isGenerated == false)
        precondition(first.entries.last?.rawGeneratedText == nil)

        let coldCancel = makeModel()
        ask(coldCancel)
        try await Task.sleep(for: .milliseconds(20))
        coldCancel.stop()
        try await settle(coldCancel)
        precondition(!coldCancel.isReady && coldCancel.entries.isEmpty && coldCancel.draft == question)
        precondition(coldCancel.modelLibrary.protectedIDs.isEmpty)

        let duplicate = makeModel()
        ask(duplicate)
        duplicate.sendWithPreparation()
        try await settle(duplicate)
        precondition(duplicate.entries.count == 1)

        let switching = makeModel()
        ask(switching)
        try await settle(switching)
        let priorEntry = switching.entries[0]
        do {
            try await switching.selectModel(id: "invalid")
            preconditionFailure("Invalid selection succeeded")
        } catch { }
        precondition(switching.isReady && switching.activeDescriptor?.id == "old")
        precondition(switching.entries[0].id == priorEntry.id)

        await EngineProbe.shared.resetEvents()
        ask(switching)
        try await Task.sleep(for: .milliseconds(20))
        try await switching.selectModel(id: "new")
        let events = await EngineProbe.shared.recordedEvents()
        let drained = events.firstIndex(of: "generation-drained:old")!
        let unloaded = events.firstIndex(of: "unload:old")!
        let replacement = events.firstIndex(of: "load-start:new")!
        precondition(drained < unloaded && unloaded < replacement)
        precondition(switching.isReady && switching.activeDescriptor?.id == "new")
        precondition(switching.modelLibrary.selectedID == "new" && switching.entries.isEmpty)
        precondition(switching.modelLibrary.protectedIDs == ["new"])
        precondition(priorEntry.modelID == "old", "Historical model attribution mutated")

        // A failed replacement must restore both usability and protection.
        await EngineProbe.shared.fail(["old"])
        do {
            try await switching.selectModel(id: "old")
            preconditionFailure("Fault-injected load succeeded")
        } catch { }
        precondition(switching.isReady && switching.activeDescriptor?.id == "new")
        precondition(switching.modelLibrary.selectedID == "new" && switching.modelLibrary.protectedIDs == ["new"])
        await EngineProbe.shared.fail([])

        // Persistence is part of the transaction, not a best-effort afterthought.
        switching.modelLibrary.failCommit = true
        do {
            try await switching.selectModel(id: "old")
            preconditionFailure("Fault-injected selection write succeeded")
        } catch { }
        precondition(switching.isReady && switching.activeDescriptor?.id == "new")
        precondition(switching.modelLibrary.selectedID == "new")
        switching.modelLibrary.failCommit = false

        // stop() cancels a replacement load but still waits for recovery.
        let pendingSwitch = Task { try await switching.selectModel(id: "old") }
        try await Task.sleep(for: .milliseconds(25))
        switching.stop()
        do { try await pendingSwitch.value; preconditionFailure("Cancelled switch succeeded") }
        catch { }
        precondition(switching.isReady && switching.activeDescriptor?.id == "new")
        precondition(switching.modelLibrary.protectedIDs == ["new"])

        // If recovery also fails, never advertise an unloaded model as ready.
        await EngineProbe.shared.fail(["old", "new"])
        do { try await switching.selectModel(id: "old"); preconditionFailure("Double failure succeeded") }
        catch { }
        precondition(!switching.isReady && switching.activeDescriptor == nil)
        precondition(switching.modelLibrary.selectedID == "new" && switching.modelLibrary.protectedIDs.isEmpty)
        await EngineProbe.shared.fail([])
        ask(switching)
        try await settle(switching)
        precondition(switching.isReady && switching.entries.last?.isGenerated == true)
        precondition(switching.activeDescriptor?.id == "new")

        let coldSwitch = makeModel()
        ask(coldSwitch)
        try await Task.sleep(for: .milliseconds(20))
        try await coldSwitch.selectModel(id: "new")
        precondition(coldSwitch.isReady && coldSwitch.entries.isEmpty && coldSwitch.draft == question)
        precondition(coldSwitch.activeDescriptor?.id == "new")
        print("PASS: persisted cold Ask, preserved edits, joined stop, duplicate Ask, cancelled preparation, invalid selection, generation drain-before-unload, successful switch/context clear/model attribution, replacement failure rollback, persistence failure rollback, switch cancellation recovery, failed recovery readiness, retry, and switch during first load. Controlled doubles only; no inference or download evidence.")
    }

    @MainActor private static func settle(_ model: ChatModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy {
            precondition(ContinuousClock.now < deadline, "Coordinator did not settle")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
