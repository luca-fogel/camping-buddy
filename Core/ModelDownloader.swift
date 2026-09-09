import Foundation

public enum ModelDownloadState: Sendable, Equatable {
    case progress(received: Int64, total: Int64)
    case verifying
    case paused(resumable: Bool)
    case failed(String)
    case ready
}

public protocol ModelFileTransport: Sendable {
    func fetch(_ url: URL, to destination: URL,
               progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// URLSession downloads into a temporary file. No response body is loaded as Data.
public struct URLSessionModelTransport: ModelFileTransport {
    public init() {}
    public func fetch(_ url: URL, to destination: URL,
                      progress: @escaping @Sendable (Int64) -> Void) async throws {
        try ModelDownloadTrust.validate(url)
        let transfer = FileTransfer(destination: destination, progress: progress)
        try await transfer.run(url)
    }
}

private final class FileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var finished = false
    private var lastProgress = Date.distantPast

    init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination; self.progress = progress
    }

    func run(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 3_600
                configuration.httpMaximumConnectionsPerHost = 1
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                lock.lock()
                self.continuation = continuation
                if cancelled {
                    lock.unlock(); finish(.failure(CancellationError())); return
                }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.downloadTask(with: url); self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.cancel() }
    }

    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<Void, any Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true; self.continuation = nil
        let session = session; self.session = nil; self.task = nil
        let wasCancelled = cancelled
        lock.unlock()
        session?.finishTasksAndInvalidate()
        if wasCancelled { continuation.resume(throwing: CancellationError()) }
        else { continuation.resume(with: result) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        do {
            guard let url = request.url else { throw ModelCatalogError.invalid("Missing redirect destination.") }
            try ModelDownloadTrust.validate(url)
            completionHandler(request)
        } catch {
            completionHandler(nil); task.cancel(); finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Delegate callbacks are serial; keep progress updates bounded even on
        // a fast connection, and never retain chunks of model data.
        let now = Date()
        if now.timeIntervalSince(lastProgress) >= 0.15 || totalBytesWritten == totalBytesExpectedToWrite {
            lastProgress = now; progress(totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try ModelDownloadTrust.validateResponse(downloadTask.response)
            lock.lock(); let wasCancelled = cancelled; lock.unlock()
            if wasCancelled { throw CancellationError() }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)) }
    }
}

public actor ModelDownloader {
    private let storage: ModelStorage
    private let transport: any ModelFileTransport
    public init(storage: ModelStorage, transport: any ModelFileTransport = URLSessionModelTransport()) {
        self.storage = storage; self.transport = transport
    }

    public func download(_ model: ModelDescriptor,
                         progress: @escaping @Sendable (ModelDownloadState) async -> Void) async throws -> InstalledModel {
        guard storage.catalog.model(id: model.id) == model else {
            throw ModelCatalogError.invalid("This model does not match the bundled catalog.")
        }
        try Task.checkCancellation()
        let stage = try await storage.beginDownload(model.id)
        do {
            var received: Int64 = 0
            await progress(.progress(received: 0, total: model.totalBytes))
            for file in model.files {
                try Task.checkCancellation()
                if try await storage.verifiedStagedFile(file, modelID: model.id) {
                    received += file.size
                    await progress(.progress(received: received, total: model.totalBytes))
                    continue
                }
                let temporary = stage.appendingPathComponent("transfer-\(UUID().uuidString)")
                let base = received
                do {
                    try await transport.fetch(model.downloadURL(for: file), to: temporary) { count in
                        let total = min(base + max(0, count), model.totalBytes)
                        Task { await progress(.progress(received: total, total: model.totalBytes)) }
                    }
                    try Task.checkCancellation()
                    try await storage.acceptDownloadedFile(temporary, file: file, modelID: model.id)
                } catch {
                    // This unique temporary file belongs to this transfer only.
                    if FileManager.default.fileExists(atPath: temporary.path) {
                        try? FileManager.default.removeItem(at: temporary)
                    }
                    throw error
                }
                received += file.size
                await progress(.progress(received: received, total: model.totalBytes))
            }
            try Task.checkCancellation()
            await progress(.verifying)
            let installed = try await storage.finishDownload(model.id)
            await storage.endDownload(model.id)
            await progress(.ready)
            return installed
        } catch {
            await storage.endDownload(model.id)
            throw error
        }
    }
}
