import Foundation
import UIKit

/// Opt-in development check of the same loading, retrieval, generation, and
/// citation-validation flow used by the visible app. No test-runner app needed.
@MainActor
enum DeviceSmokeTest {
    private static var hasRun = false
    private static let question = "What sleeping gear should I pack?"

    static func runIfRequested(model: ChatModel) async {
        guard CommandLine.arguments.contains("--camping-smoke-test"), !hasRun else { return }
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
            if didAsk { model.stop() }
            let cancelled = error is CancellationError || Task.isCancelled
            writeReport(model: model, entryID: entryID, runID: runID, startedAt: startedAt,
                        status: cancelled ? "cancelled" : "failed",
                        phase: phase,
                        detail: cancelled ? "The on-device check was cancelled." : error.localizedDescription)
        }
    }

    private static func waitUntil(stage: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while !condition() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw CheckFailure.timedOut(stage) }
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
            case .timedOut(let stage): "The on-device check timed out after 120 seconds waiting for \(stage). Stop was requested."
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
        let modelReady: Bool
        let modelLoading: Bool
        let modelGenerating: Bool
        let preparingQuestion: Bool
        let libraryError: String?
        let deviceModel: String
        let systemName: String
        let systemVersion: String
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
            modelStatus: model.status, metrics: model.metrics,
            modelReady: model.isReady, modelLoading: model.isLoading, modelGenerating: model.isGenerating,
            preparingQuestion: model.isPreparingQuestion,
            libraryError: model.libraryError,
            deviceModel: UIDevice.current.model,
            systemName: UIDevice.current.systemName, systemVersion: UIDevice.current.systemVersion,
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
}
