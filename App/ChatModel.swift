import Foundation
import SwiftUI

struct ChatEntry: Identifiable {
    let id = UUID()
    let question: String
    var answer: String
    var sources: [ReferencePassage]
    var isGenerated: Bool = false
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var library: ReferenceLibrary?
    @Published var entries: [ChatEntry] = []
    @Published var draft = ""
    @Published var status = "Model has not been loaded"
    @Published var isLoading = false
    @Published var isReady = false
    @Published var isGenerating = false
    @Published private(set) var isPreparingQuestion = false
    @Published var metrics = "No model run measured yet."
    @Published var libraryError: String?
    private let engine = LocalModelEngine()
    private var generationTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?

    var isBusy: Bool { isLoading || isGenerating || isPreparingQuestion }

    var canSend: Bool {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isGenerating && !isPreparingQuestion && !question.isEmpty
            && question.count <= 1200 && library != nil
    }

    var modelStateLabel: String {
        if isGenerating { return "Answering on device" }
        if isLoading || isPreparingQuestion { return "Preparing your model" }
        if isReady { return "Ready on device" }
        #if targetEnvironment(simulator)
        return "Reference preview"
        #else
        return "Loads when you ask"
        #endif
    }

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "references", withExtension: "json", subdirectory: "ReferenceLibrary") else {
                throw CocoaError(.fileNoSuchFile)
            }
            library = try ReferenceLibrary(data: Data(contentsOf: url))
        } catch { libraryError = "The bundled reference library could not be opened. Reinstall a complete build. \(error.localizedDescription)" }
    }

    func loadModel() {
        guard !isLoading, !isGenerating, !isReady else { return }
        #if targetEnvironment(simulator)
        status = "Reference-library preview only. Local MLX generation requires an Apple device, not this simulator."
        return
        #else
        isLoading = true
        status = "Loading Gemma 4 E2B from this device…"
        loadTask = Task { await performLoad() }
        #endif
    }

    private func performLoad() async {
        defer { isLoading = false; loadTask = nil }
        do {
            guard let resource = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let seconds = try await engine.load(directory: resource.appendingPathComponent("Models/gemma-4-E2B-it-4bit"))
            isReady = true
            status = "Gemma 4 E2B ready · local files only"
            metrics = String(format: "Model load: %.2f seconds. No answer measured yet.", seconds)
        } catch {
            status = Task.isCancelled ? "Loading stopped. You can retry when ready." : "Model unavailable: \(error.localizedDescription)"
        }
    }

    func send() {
        guard !isPreparingQuestion else { return }
        let originalDraft = draft
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        submit(question: question, clearingDraft: originalDraft)
    }

    /// The primary Ask action. Keep the captured question until preparation
    /// succeeds, and never replace edits the user makes while the model loads.
    func sendWithPreparation() {
        guard canSend else { return }
        let originalDraft = draft
        let question = originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        // These routes provide an honest library/scope response without inference.
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
                // A failed load leaves the original draft available to retry.
                guard isReady else { return }
                submit(question: question, clearingDraft: originalDraft)
            } catch {
                // stop() also cancels the loading task. No question is submitted
                // after cancellation, even if the model finishes loading first.
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
        guard !question.isEmpty, !isGenerating, question.count <= 1200 else { return }
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
        guard isReady else {
            entries.append(ChatEntry(question: question, answer: "Load the bundled model to generate an answer. You can read these relevant reference passages now.", sources: passages))
            return
        }
        isGenerating = true
        entries.append(ChatEntry(question: question, answer: "Reading the local references…", sources: passages))
        let id = entries.last!.id
        generationTask = Task {
            defer { isGenerating = false; generationTask = nil }
            do {
                let result = try await engine.answer(prompt: AnswerPolicy.prompt(question: question, passages: passages))
                try Task.checkCancellation()
                let checked = try AnswerPolicy.check(result.text, supplied: passages)
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    entries[index].answer = checked.text
                    entries[index].sources = passages.filter { checked.citedIDs.contains($0.id) }
                    entries[index].isGenerated = true
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
        if isLoading { status = "Stopping model load…" }
    }
}
