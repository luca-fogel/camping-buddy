import Foundation

struct CampingGeneration: Sendable {
    let text: String
    let metrics: String
    let modelID: String
    let modelName: String
}

/// Dispatches only to the local MLX engine. ChatModel joins active work before switching.
actor CampingModelEngine {
    private let mlx = LocalModelEngine()
    private var descriptor: ModelDescriptor?

    func load(directory: URL?, model: ModelDescriptor) async throws -> Double {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        guard let directory else { throw LocalModelEngine.Failure.notLoaded }
        _ = try await mlx.load(directory: directory, model: model)
        try Task.checkCancellation()
        descriptor = model
        let duration = started.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    func unload() async throws {
        try await mlx.unload()
        descriptor = nil
    }

    func answer(prompt: String) async throws -> CampingGeneration {
        guard let descriptor else { throw LocalModelEngine.Failure.notLoaded }
        let result = try await mlx.answer(prompt: prompt)
        try Task.checkCancellation()
        return CampingGeneration(text: result.text, metrics: result.metrics,
                                 modelID: descriptor.id, modelName: descriptor.name)
    }
}
