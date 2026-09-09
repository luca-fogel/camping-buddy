import Foundation
import SwiftUI

struct ChatEntry: Identifiable {
    let id = UUID()
    let question: String
    var answer: String
    var sources: [ReferencePassage]
    var isGenerated: Bool = false
    // A response keeps its identity even when the selected model later changes.
    var modelID: String? = nil
    var modelName: String? = nil
    var metrics: String? = nil
    // Diagnostics only: the UI displays answer after the source check succeeds.
    var rawGeneratedText: String? = nil
}

@MainActor
final class ChatModel: ObservableObject {
    let modelLibrary: ModelLibrary
    @Published var library: ReferenceLibrary?
    @Published var entries: [ChatEntry] = []
    @Published var draft = ""
    @Published var status = "Model has not been loaded"
    @Published var isLoading = false
    @Published var isReady = false
    @Published var isGenerating = false
    @Published private(set) var isPreparingQuestion = false
    @Published private(set) var isSwitchingModel = false
    @Published private(set) var activeDescriptor: ModelDescriptor?
    @Published var metrics = "No model run measured yet."
    @Published var libraryError: String?
    private let engine = CampingModelEngine()
    private var activeDirectory: URL?
    private var generationTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Error>?

    var isBusy: Bool { isLoading || isGenerating || isPreparingQuestion || isSwitchingModel }

    var selectedModelName: String {
        modelLibrary.descriptor(for: modelLibrary.selectedID)?.name ?? "Local model"
    }

    var canSend: Bool {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isGenerating && !isPreparingQuestion && !isSwitchingModel && !question.isEmpty
            && question.count <= 1200 && library != nil
    }

    var modelStateLabel: String {
        if isSwitchingModel { return "Switching models" }
        if isGenerating { return "Answering on device" }
        if isLoading || isPreparingQuestion { return "Preparing your model" }
        if isReady { return "Ready on device" }
        #if targetEnvironment(simulator)
        return "Reference preview"
        #else
        return "Loads when you ask"
        #endif
    }

    init(modelLibrary: ModelLibrary) {
        self.modelLibrary = modelLibrary
        do {
            guard let url = Bundle.main.url(forResource: "references", withExtension: "json", subdirectory: "ReferenceLibrary") else {
                throw CocoaError(.fileNoSuchFile)
            }
            library = try ReferenceLibrary(data: Data(contentsOf: url))
        } catch { libraryError = "The bundled reference library could not be opened. Reinstall a complete build. \(error.localizedDescription)" }
    }

    func loadModel() {
        guard !isLoading, !isGenerating, !isReady, !isSwitchingModel else { return }
        #if targetEnvironment(simulator)
        status = "Reference-library preview only. Local MLX generation requires an Apple device, not this simulator."
        return
        #else
        isLoading = true
        status = "Preparing the selected model from this device…"
        loadTask = Task { await performLoad() }
        #endif
    }

    private func performLoad() async {
        defer { isLoading = false; loadTask = nil }
        var protectedID: String?
        do {
            await modelLibrary.prepare()
            try Task.checkCancellation()
            let id = modelLibrary.selectedID
            guard let descriptor = modelLibrary.descriptor(for: id) else {
                throw SelectionFailure.unavailable
            }
            let directory = try await modelDirectory(for: descriptor)
            try await modelLibrary.protect(id)
            protectedID = id
            try Task.checkCancellation()
            status = "Loading \(descriptor.name) from this device…"
            let seconds = try await engine.load(directory: directory, model: descriptor)
            try Task.checkCancellation()
            activeDescriptor = descriptor
            activeDirectory = directory
            isReady = true
            status = "\(descriptor.name) ready · on this device"
            metrics = loadMetrics(descriptor: descriptor, seconds: seconds)
        } catch {
            try? await engine.unload()
            if let protectedID { await modelLibrary.unprotect(protectedID) }
            activeDescriptor = nil
            activeDirectory = nil
            isReady = false
            status = Task.isCancelled ? "Loading stopped. You can retry when ready." : "Model unavailable: \(error.localizedDescription)"
        }
    }

    /// The selection is persisted only after the replacement is usable. The
    /// previous selection stays protected until success or a rollback reload.
    func selectModel(id: String) async throws {
        guard !isSwitchingModel else { throw SelectionFailure.switchInProgress }
        #if targetEnvironment(simulator)
        throw SelectionFailure.simulator
        #else
        isSwitchingModel = true
        let task = Task { try await performSelection(id: id) }
        selectionTask = task
        defer { isSwitchingModel = false; selectionTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        #endif
    }

    private func performSelection(id: String) async throws {
        await modelLibrary.prepare()
        try Task.checkCancellation()
        guard let descriptor = modelLibrary.descriptor(for: id) else {
            throw SelectionFailure.unavailable
        }
        if isReady, activeDescriptor?.id == id { return }
        // Cancel and join every task that can hold a model or submit a question.
        // The engine itself joins the low-level generation computation.
        await cancelAndWaitForRequests()
        try Task.checkCancellation()
        let previousDescriptor = activeDescriptor
        let previousDirectory = activeDirectory
        let previousID = previousDescriptor?.id
        let directory = try await modelDirectory(for: descriptor)
        if previousID != id { try await modelLibrary.protect(id) }
        do {
            try Task.checkCancellation()
            try await engine.unload()
        } catch {
            if previousID != id { await modelLibrary.unprotect(id) }
            throw error
        }
        activeDescriptor = nil
        activeDirectory = nil
        isReady = false
        isLoading = true
        defer { isLoading = false }
        status = "Loading \(descriptor.name) from this device…"
        do {
            let seconds = try await engine.load(directory: directory, model: descriptor)
            try Task.checkCancellation()
            try await modelLibrary.commitSelection(id)
            // Commit is the transaction boundary. Do not report cancellation
            // after a successful durable selection as a failed switch.
            activeDescriptor = descriptor
            activeDirectory = directory
            isReady = true
            entries.removeAll()
            status = "\(descriptor.name) ready · on this device"
            metrics = loadMetrics(descriptor: descriptor, seconds: seconds)
            if let previousID, previousID != id { await modelLibrary.unprotect(previousID) }
        } catch {
            let originalError = error
            try? await engine.unload()
            // Rollback must finish even when the user cancelled the switch.
            // A fresh task avoids inheriting that cancelled task's state.
            if let previousDescriptor {
                status = "Restoring \(previousDescriptor.name)…"
                let recovery = Task {
                    try await engine.load(directory: previousDirectory, model: previousDescriptor)
                }
                do {
                    let seconds = try await recovery.value
                    activeDescriptor = previousDescriptor
                    activeDirectory = previousDirectory
                    isReady = true
                    metrics = loadMetrics(descriptor: previousDescriptor, seconds: seconds)
                    status = "Could not switch models. \(previousDescriptor.name) is ready again."
                } catch {
                    try? await engine.unload()
                    await modelLibrary.unprotect(previousDescriptor.id)
                    status = "Model switch failed, and the previous model could not reload. Ask again to retry. \(error.localizedDescription)"
                }
            } else {
                status = "Model unavailable: \(originalError.localizedDescription)"
            }
            if previousID != id { await modelLibrary.unprotect(id) }
            if originalError is CancellationError { throw CancellationError() }
            throw SelectionFailure.failed("\(originalError.localizedDescription) \(isReady ? "The previous model was restored." : "No model is currently ready.")")
        }
    }

    private func cancelAndWaitForRequests() async {
        let preparation = preparationTask
        let loading = loadTask
        let generation = generationTask
        preparation?.cancel()
        loading?.cancel()
        generation?.cancel()
        await preparation?.value
        await loading?.value
        await generation?.value
    }

    private func loadMetrics(descriptor: ModelDescriptor, seconds: Double) -> String {
        "\(descriptor.name) [\(descriptor.id)] · " + String(
            format: "Model load: %.2f seconds. No answer measured for this load yet.", seconds)
    }

    private func modelDirectory(for descriptor: ModelDescriptor) async throws -> URL? {
        try await modelLibrary.directory(for: descriptor.id)
    }

    func send() {
        guard !isPreparingQuestion, !isSwitchingModel else { return }
        let originalDraft = draft
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        submit(question: question, clearingDraft: originalDraft)
    }

    /// The primary Ask action captures the question, then prepares the persisted
    /// selection. Edits made during the load remain available as the next draft.
    func sendWithPreparation() {
        guard canSend else { return }
        let originalDraft = draft
        let question = originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if isReady || AnswerPolicy.requestsOverride(question) || AnswerPolicy.outsideScope(question)
            || library?.search(question).isEmpty == true {
            submit(question: question, clearingDraft: originalDraft)
            return
        }
        #if targetEnvironment(simulator)
        loadModel()
        return
        #else
        isPreparingQuestion = true
        preparationTask = Task {
            defer { isPreparingQuestion = false; preparationTask = nil }
            do {
                try Task.checkCancellation()
                if !isReady {
                    loadModel()
                    if let loadTask { await loadTask.value }
                }
                try Task.checkCancellation()
                guard isReady else { return }
                submit(question: question, clearingDraft: originalDraft)
            } catch {
                if !isLoading && !isReady { status = "Preparation stopped. Edit your question or ask again." }
            }
        }
        #endif
    }

    @discardableResult
    func clearConversation() -> Bool {
        guard !isBusy else { return false }
        entries.removeAll()
        draft = ""
        return true
    }

    private func submit(question: String, clearingDraft originalDraft: String) {
        guard !question.isEmpty, !isGenerating, !isSwitchingModel, question.count <= 1200 else { return }
        guard let library else { return }
        if draft == originalDraft { draft = "" }
        if entries.count >= 12 { entries.removeFirst() }
        if AnswerPolicy.requestsOverride(question) {
            entries.append(ChatEntry(question: question, answer: AnswerPolicy.overrideMessage, sources: library.search(question)))
            return
        }
        if AnswerPolicy.outsideScope(question) {
            entries.append(ChatEntry(question: question, answer: AnswerPolicy.scopeMessage, sources: []))
            return
        }
        let passages = library.search(question)
        guard !passages.isEmpty else {
            entries.append(ChatEntry(question: question, answer: AnswerPolicy.noEvidence, sources: []))
            return
        }
        guard isReady, let descriptor = activeDescriptor else {
            entries.append(ChatEntry(question: question, answer: "Prepare the selected model to generate an answer. You can read these relevant reference passages now.", sources: passages))
            return
        }
        isGenerating = true
        entries.append(ChatEntry(question: question, answer: "Reading the local references…", sources: passages,
                                 modelID: descriptor.id, modelName: descriptor.name))
        let id = entries.last!.id
        generationTask = Task {
            defer { isGenerating = false; generationTask = nil }
            do {
                let result = try await engine.answer(prompt: AnswerPolicy.prompt(question: question, passages: passages))
                try Task.checkCancellation()
                guard result.modelID == descriptor.id else {
                    throw SelectionFailure.failed("The answer's model identity did not match the request. The answer was withheld.")
                }
                metrics = result.metrics
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    entries[index].metrics = result.metrics
                    entries[index].rawGeneratedText = result.text
                }
                let checked = try AnswerPolicy.check(result.text, supplied: passages)
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    entries[index].answer = checked.text
                    entries[index].sources = passages.filter { checked.citedIDs.contains($0.id) }
                    entries[index].isGenerated = true
                    entries[index].metrics = result.metrics
                }
                metrics = result.metrics
            } catch {
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    if error is CancellationError || Task.isCancelled {
                        entries[index].answer = "Answer stopped. The reference passages are still available below."
                    } else if error is AnswerPolicy.CitationError {
                        entries[index].answer = "The generated answer did not pass the source-reference check, so it was withheld. Read the supplied passages below or try a more specific question."
                    } else {
                        entries[index].answer = "Local generation failed: \(error.localizedDescription). The reference passages remain available."
                    }
                }
            }
        }
    }

    func stop() {
        preparationTask?.cancel()
        generationTask?.cancel()
        loadTask?.cancel()
        selectionTask?.cancel()
        if isSwitchingModel { status = "Stopping the switch and restoring the previous model…" }
        else if isLoading { status = "Stopping model load…" }
    }

    /// Development checks can join cancellation, including rollback, before
    /// writing their final result. The interactive Stop button stays immediate.
    func stopAndWait() async {
        let selection = selectionTask
        stop()
        await cancelAndWaitForRequests()
        _ = try? await selection?.value
    }

    private enum SelectionFailure: LocalizedError {
        case unavailable
        case switchInProgress
        case simulator
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "The selected model is unavailable in this model library."
            case .switchInProgress: "A model switch is already in progress. Wait for it to finish."
            case .simulator: "The simulator can preview the library, but loading MLX models requires a physical Apple device."
            case .failed(let detail): detail
            }
        }
    }
}
