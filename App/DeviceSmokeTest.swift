import Foundation
import UIKit

/// Opt-in development check of the same loading, retrieval, generation, and
/// citation-validation flow used by the visible app. No test-runner app needed.
@MainActor
enum DeviceSmokeTest {
    private static var hasRun = false
    private static let question = "What sleeping gear should I pack?"

    static func runIfRequested(model: ChatModel) async {
        guard !hasRun else { return }
        if CommandLine.arguments.contains("--camping-model-manager-smoke") {
            hasRun = true
            await runModelManager(model: model)
            return
        }
        guard CommandLine.arguments.contains("--camping-smoke-test") else { return }
        hasRun = true

        let runID = UUID()
        let startedAt = Date()
        var entryID: UUID?
        var phase = "cold_start"
        var didAsk = false
        writeReport(model: model, entryID: nil, runID: runID, startedAt: startedAt,
                    status: "running", phase: phase,
                    detail: "Checking a cold start before one Ask action prepares the model and answers.")

        do {
            try Task.checkCancellation()
            guard !model.isReady, !model.isBusy, model.entries.isEmpty else {
                throw CheckFailure.failed("This check requires a fresh ChatModel with no loaded model, active request, or conversation. Relaunch with the test flag.")
            }
            guard model.library != nil else {
                throw CheckFailure.failed(model.libraryError ?? "The bundled reference library is unavailable.")
            }
            let previousIDs = Set(model.entries.map(\.id))
            model.draft = question
            didAsk = true
            model.sendWithPreparation()
            try await waitUntil(stage: "the first Ask to prepare the model and generate an answer") {
                if let entry = model.entries.last,
                   entry.question == question, !previousIDs.contains(entry.id) {
                    entryID = entry.id
                }
                let nextPhase = model.isGenerating ? "generating" : (model.isBusy ? "preparing_model" : "checking_result")
                if nextPhase != phase {
                    phase = nextPhase
                    writeReport(model: model, entryID: entryID, runID: runID, startedAt: startedAt,
                                status: "running", phase: phase,
                                detail: "Observing the single Ask action through the visible app's normal flow.")
                }
                return !model.isBusy
            }
            guard model.isReady else { throw CheckFailure.failed("The first Ask did not prepare the local model: \(model.status)") }
            guard let entryID else {
                throw CheckFailure.failed("The chat flow did not create the test question.")
            }
            guard let result = model.entries.first(where: { $0.id == entryID }), result.isGenerated,
                  !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.sources.isEmpty else {
                throw CheckFailure.failed("The app did not accept a real generated answer with validated local source references.")
            }
            try Task.checkCancellation()
            writeReport(model: model, entryID: entryID, runID: runID, startedAt: startedAt,
                        status: "passed", phase: "completed",
                        detail: "One Ask action from a cold ChatModel prepared the local model and produced an accepted real answer with validated local source references.")
        } catch {
            if didAsk { await model.stopAndWait() }
            let cancelled = error is CancellationError || Task.isCancelled
            writeReport(model: model, entryID: entryID, runID: runID, startedAt: startedAt,
                        status: cancelled ? "cancelled" : "failed",
                        phase: phase,
                        detail: cancelled ? "The on-device check was cancelled." : error.localizedDescription)
        }
    }

    private static func waitUntil(stage: String, seconds: Int = 120, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw CheckFailure.timedOut("\(stage) (\(seconds)-second deadline)") }
            try await Task.sleep(for: .milliseconds(250))
        }
        try Task.checkCancellation()
    }

    private enum CheckFailure: LocalizedError {
        case failed(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            case .timedOut(let stage): "The on-device check timed out waiting for \(stage). Stop was requested."
            }
        }
    }

    private struct Report: Encodable {
        let runID: UUID
        var status: String
        let phase: String
        let workflow: String
        var detail: String
        let startedAt: Date
        let recordedAt: Date
        let question: String
        let generatedAnswer: Bool
        let answer: String?
        let displayedMessage: String?
        let sources: [ReferencePassage]
        let modelStatus: String
        let metrics: String
        let modelID: String?
        let modelName: String?
        let generationCompleted: Bool
        let rawGeneratedText: String?
        let modelReady: Bool
        let modelLoading: Bool
        let modelGenerating: Bool
        let preparingQuestion: Bool
        let libraryError: String?
        let deviceModel: String
        let systemName: String
        let systemVersion: String
        let appVersion: String?
        let buildNumber: String?
        let simulator: Bool
        let testContext: String
        let offlineVerified: Bool
        let connectivityChangedByTest: Bool
        var artifactWriteError: String?
    }

    private static func writeReport(
        model: ChatModel, entryID: UUID?, runID: UUID, startedAt: Date,
        status: String, phase: String, detail: String
    ) {
        let entry = model.entries.first { $0.id == entryID }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        var report = Report(
            runID: runID, status: status, phase: phase, workflow: "single_ask_from_cold_chat_model",
            detail: detail, startedAt: startedAt, recordedAt: Date(),
            question: question, generatedAnswer: entry?.isGenerated == true,
            answer: entry?.isGenerated == true ? entry?.answer : nil,
            displayedMessage: entry?.answer, sources: entry?.sources ?? [],
            modelStatus: model.status, metrics: entry?.metrics ?? model.metrics,
            modelID: entry?.modelID ?? model.activeDescriptor?.id,
            modelName: entry?.modelName ?? model.activeDescriptor?.name,
            generationCompleted: entry?.rawGeneratedText != nil,
            rawGeneratedText: entry?.rawGeneratedText,
            modelReady: model.isReady, modelLoading: model.isLoading, modelGenerating: model.isGenerating,
            preparingQuestion: model.isPreparingQuestion,
            libraryError: model.libraryError,
            deviceModel: UIDevice.current.model,
            systemName: UIDevice.current.systemName, systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            simulator: simulator,
            testContext: "Development smoke test launched from a connected Mac. Networking was not disabled for this check. The app does not measure Mac connection or radio state. This is not the Mac-off, cold-launch offline acceptance test.",
            offlineVerified: false, connectivityChangedByTest: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let destination = documents.appendingPathComponent("DeviceSmokeTest.json")
            try encoder.encode(report).write(to: destination, options: .atomic)
        } catch {
            report.status = "failed"
            report.artifactWriteError = error.localizedDescription
            report.detail += " Could not save DeviceSmokeTest.json in this app's Documents folder."
        }
        // A single-line marker allows the connected development tool to capture
        // the same report. The fixed file is the only artifact overwritten.
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
            print("CAMPING_DEVICE_SMOKE_TEST \(json)")
        } else {
            print("CAMPING_DEVICE_SMOKE_TEST {\"status\":\"failed\",\"detail\":\"Could not encode the on-device check report.\"}")
        }
    }

    private static let managerModelID = "ternary-bonsai-8b-2bit"

    private struct ModelRun: Encodable {
        let requestedModelID: String
        let requestedRevision: String?
        let selectedModelID: String
        let loadedModelID: String?
        let loadedRevision: String?
        let answerModelID: String?
        let modelName: String?
        let generationCompleted: Bool
        let citationAccepted: Bool
        let answer: String?
        let rawGeneratedText: String?
        let displayedMessage: String?
        let sources: [ReferencePassage]
        let metrics: String
        let modelStatus: String
    }

    private struct ManagerReport: Encodable {
        let runID = UUID()
        let startedAt = Date()
        var recordedAt = Date()
        var status = "running"
        var phase = "preparing_library"
        var detail = "Preparing the actual model library for one approved model download."
        let workflow = "download_select_generate_cancel"
        let downloadedModelID: String
        let question: String
        var downloadStatus = "not_started"
        var downloadedThisRun = false
        var downloadSeconds: Double?
        var firstModel: ModelRun?
        var invalidSelectionRejected = false
        var inUseModelDeletionRejected = false
        var cancellationRequestedDuringGeneration = false
        var generationCancelled = false
        var selectedModelID: String?
        var activeModelID: String?
        var modelReady = false
        let deviceModel: String
        let systemName: String
        let systemVersion: String
        let appVersion: String?
        let buildNumber: String?
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let testContext = "Development smoke test launched from a connected Mac. Networking is required for the model download and was not disabled. The app does not measure Mac connection or radio state. This is not the Mac-off, cold-launch offline acceptance test."
        let offlineVerified = false
        let connectivityChangedByTest = false
        let memoryMeasurement = "Metrics report the MLX allocator's process-lifetime peak, not total app RSS. The Mac evaluation peaked at 2,584 MiB for this model; the phone figure is unknown until this check runs."

        @MainActor init() {
            downloadedModelID = DeviceSmokeTest.managerModelID
            question = DeviceSmokeTest.question
            deviceModel = UIDevice.current.model
            systemName = UIDevice.current.systemName
            systemVersion = UIDevice.current.systemVersion
            appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        }
    }

    /// This second, explicit flag exercises the real downloader and model
    /// selection coordinator. It never supplies responses or alters radios.
    private static func runModelManager(model: ChatModel) async {
        var report = ManagerReport()
        writeManagerReport(model: model, report: &report)
        let library = model.modelLibrary
        do {
            #if targetEnvironment(simulator)
            throw CheckFailure.failed("The model-manager inference check requires a physical Apple device; the simulator is a library preview only.")
            #else
            try Task.checkCancellation()
            guard !model.isBusy, model.library != nil else {
                throw CheckFailure.failed("The chat must be idle with its real reference library available.")
            }
            await library.prepare()
            guard library.descriptor(for: managerModelID) != nil else {
                throw CheckFailure.failed("The shipped model is absent from this build's catalog.")
            }
            if (try? await library.directory(for: managerModelID)) != nil {
                report.downloadStatus = "already_installed_verified_copy_reused"
                report.detail = "The approved model is already installed. This run will reuse it and will not claim a new download."
            } else {
                report.phase = "downloading_approved_model"
                report.downloadStatus = "downloading"
                writeManagerReport(model: model, report: &report)
                let started = ContinuousClock.now
                library.download(managerModelID)
                try await performBounded(stage: "the approved model download", seconds: 600,
                                         onCancel: { library.cancelDownload(managerModelID) }) {
                    try await library.awaitDownload(managerModelID)
                }
                _ = try await library.directory(for: managerModelID)
                let elapsed = started.duration(to: .now).components
                report.downloadSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                report.downloadedThisRun = true
                report.downloadStatus = "downloaded_and_verified"
            }
            report.phase = "loading_downloaded_model"
            report.detail = "Loading the shipped model through the same model manager as the visible app."
            writeManagerReport(model: model, report: &report)
            try await performBounded(stage: "the downloaded model to load", onCancel: { model.stop() }) {
                try await model.selectModel(id: managerModelID)
            }
            report.phase = "generating_with_downloaded_model"
            writeManagerReport(model: model, report: &report)
            report.firstModel = try await askAndCapture(model: model, requestedID: managerModelID)
            // These rejection checks must leave the usable selection intact.
            do { try await model.selectModel(id: "not-a-catalog-model") }
            catch { report.invalidSelectionRejected = true }
            guard report.invalidSelectionRejected, model.isReady,
                  model.activeDescriptor?.id == managerModelID, library.selectedID == managerModelID else {
                throw CheckFailure.failed("An invalid selection did not leave the previous model ready and selected.")
            }
            // The loaded model is held by the chat coordinator, so its files
            // must stay put. Removal is allowed once nothing is using them.
            do { try await library.remove(managerModelID) }
            catch { report.inUseModelDeletionRejected = true }
            guard report.inUseModelDeletionRejected,
                  (try? await library.directory(for: managerModelID)) != nil else {
                throw CheckFailure.failed("The model manager did not protect the in-use model from deletion.")
            }
            // A source-check failure is recorded independently. It must not
            // prevent exercising cancellation of a real generation.
            report.phase = "cancelling_generation"
            report.detail = "Starting a real request, then stopping it to exercise cancellation and joining the prior generation."
            model.draft = question
            model.sendWithPreparation()
            try await Task.sleep(for: .milliseconds(250))
            report.cancellationRequestedDuringGeneration = model.isGenerating
            writeManagerReport(model: model, report: &report)
            await model.stopAndWait()
            report.generationCancelled = !model.isGenerating && !model.isBusy
            let runs = [report.firstModel].compactMap { $0 }
            let accepted = report.invalidSelectionRejected && report.inUseModelDeletionRejected &&
                report.cancellationRequestedDuringGeneration && report.generationCancelled &&
                runs.count == 1 && runs.allSatisfy {
                $0.generationCompleted && $0.citationAccepted &&
                $0.requestedModelID == $0.selectedModelID &&
                $0.requestedModelID == $0.loadedModelID &&
                $0.requestedModelID == $0.answerModelID &&
                $0.requestedRevision != nil && $0.requestedRevision == $0.loadedRevision
            }
            report.status = accepted ? "passed" : "failed"
            report.phase = "completed"
            report.detail = accepted
                ? "The real model run finished and passed the app's source-reference check, and a second generation was cancelled cleanly. Check downloadedThisRun to distinguish a new download from an existing verified installation."
                : "The model-manager sequence completed, but the real answer failed generation, source validation, or model-identity checks. Each stage is reported separately; no failed answer is marked accepted."
            #endif
        } catch {
            library.cancelDownload(managerModelID)
            await model.stopAndWait()
            report.status = error is CancellationError || Task.isCancelled ? "cancelled" : "failed"
            report.detail = error.localizedDescription
        }
        writeManagerReport(model: model, report: &report)
    }

    private static func askAndCapture(model: ChatModel, requestedID: String) async throws -> ModelRun {
        guard model.isReady, model.activeDescriptor?.id == requestedID,
              model.modelLibrary.selectedID == requestedID else {
            throw CheckFailure.failed("The requested model did not become the loaded and persisted selection.")
        }
        let previousIDs = Set(model.entries.map(\.id))
        model.draft = question
        model.sendWithPreparation()
        do {
            try await waitUntil(stage: "a real answer from \(requestedID)") { !model.isBusy }
        } catch {
            await model.stopAndWait()
            throw error
        }
        let entry = model.entries.last { !previousIDs.contains($0.id) && $0.question == question }
        return ModelRun(
            requestedModelID: requestedID,
            requestedRevision: model.modelLibrary.descriptor(for: requestedID)?.revision,
            selectedModelID: model.modelLibrary.selectedID,
            loadedModelID: model.activeDescriptor?.id, loadedRevision: model.activeDescriptor?.revision,
            answerModelID: entry?.modelID,
            modelName: entry?.modelName, generationCompleted: entry?.rawGeneratedText != nil,
            citationAccepted: entry?.isGenerated == true && entry?.sources.isEmpty == false,
            answer: entry?.isGenerated == true ? entry?.answer : nil,
            rawGeneratedText: entry?.rawGeneratedText, displayedMessage: entry?.answer,
            sources: entry?.sources ?? [], metrics: entry?.metrics ?? model.metrics,
            modelStatus: model.status)
    }

    /// Polling remains bounded, and cancellation is forwarded to the actual
    /// operation before its task is joined. No detached work outlives this check.
    private static func performBounded(
        stage: String, seconds: Int = 120,
        onCancel: @escaping @MainActor () -> Void,
        operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        var result: Result<Void, Error>?
        let task = Task { @MainActor in
            do { try await operation(); result = .success(()) }
            catch { result = .failure(error) }
        }
        do {
            try await waitUntil(stage: stage, seconds: seconds) { result != nil }
            try result?.get()
        } catch {
            onCancel()
            task.cancel()
            await task.value
            throw error
        }
        await task.value
    }

    private static func writeManagerReport(model: ChatModel, report: inout ManagerReport) {
        report.recordedAt = Date()
        report.selectedModelID = model.modelLibrary.selectedID
        report.activeModelID = model.activeDescriptor?.id
        report.modelReady = model.isReady
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try encoder.encode(report).write(
                to: documents.appendingPathComponent("ModelManagerSmokeTest.json"), options: .atomic)
        } catch {
            report.status = "failed"
            report.detail += " Could not save ModelManagerSmokeTest.json: \(error.localizedDescription)"
        }
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
            print("CAMPING_MODEL_MANAGER_SMOKE_TEST \(json)")
        }
    }
}
