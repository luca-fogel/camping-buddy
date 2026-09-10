import Foundation

public enum ModelCatalogError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

public enum ModelRuntime: String, Codable, Sendable { case mlx }

public enum SystemPromptMode: String, Codable, Sendable { case system, prependUser }

public struct ModelChatOptions: Codable, Sendable, Equatable {
    public let enableThinking: Bool?
    public let temperature: Float
    public let topP: Float
    public let topK: Int
    public let systemPromptMode: SystemPromptMode

    public init(enableThinking: Bool? = nil, temperature: Float = 0.7, topP: Float = 0.95,
                topK: Int = 40, systemPromptMode: SystemPromptMode = .system) {
        self.enableThinking = enableThinking; self.temperature = temperature
        self.topP = topP; self.topK = topK; self.systemPromptMode = systemPromptMode
    }

    private enum CodingKeys: String, CodingKey { case enableThinking, temperature, topP, topK, systemPromptMode }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enableThinking = try c.decodeIfPresent(Bool.self, forKey: .enableThinking)
        temperature = try c.decode(Float.self, forKey: .temperature)
        topP = try c.decode(Float.self, forKey: .topP)
        topK = try c.decode(Int.self, forKey: .topK)
        systemPromptMode = try c.decodeIfPresent(SystemPromptMode.self, forKey: .systemPromptMode) ?? .system
    }
}

public struct ModelFile: Codable, Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let sha256: String?
    public let gitBlobSHA: String?
    public init(path: String, size: Int64, sha256: String? = nil, gitBlobSHA: String? = nil) {
        self.path = path; self.size = size; self.sha256 = sha256; self.gitBlobSHA = gitBlobSHA
    }
}

public struct ModelDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let family: String
    public let repository: String
    public let revision: String
    public let totalBytes: Int64
    public let files: [ModelFile]
    public let license: String
    public let provenance: String
    public let bundledRelativePath: String?
    public let modelType: String
    public let textModelType: String?
    public let quantizationBits: Int
    public let compatibilityNote: String
    public let parameterCount: String?
    public let validationStatus: String?
    public let chatOptions: ModelChatOptions
    /// Absent in legacy catalogs; those entries continue to use MLX.
    public let runtime: ModelRuntime?
    public var backend: ModelRuntime { runtime ?? .mlx }
    public var isBundled: Bool { bundledRelativePath != nil }

    public init(id: String, name: String, family: String, repository: String, revision: String,
                totalBytes: Int64, files: [ModelFile], license: String, provenance: String,
                bundledRelativePath: String? = nil, modelType: String, textModelType: String? = nil,
                quantizationBits: Int, compatibilityNote: String, parameterCount: String? = nil,
                validationStatus: String? = nil, chatOptions: ModelChatOptions = .init(),
                runtime: ModelRuntime? = nil) {
        self.id = id; self.name = name; self.family = family; self.repository = repository
        self.revision = revision; self.totalBytes = totalBytes; self.files = files; self.license = license
        self.provenance = provenance; self.bundledRelativePath = bundledRelativePath
        self.modelType = modelType; self.textModelType = textModelType; self.quantizationBits = quantizationBits
        self.compatibilityNote = compatibilityNote; self.parameterCount = parameterCount
        self.validationStatus = validationStatus; self.chatOptions = chatOptions
        self.runtime = runtime
    }

    public func downloadURL(for file: ModelFile) throws -> URL {
        guard files.contains(file), ModelCatalog.safeRelativePath(file.path),
              let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)") else {
            throw ModelCatalogError.invalid("The model file is not in the trusted catalog.")
        }
        try ModelDownloadTrust.validate(url)
        return url
    }
}

public struct ModelCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let defaultModelID: String
    public let models: [ModelDescriptor]
    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        try validate()
    }
    public init(defaultModelID: String, models: [ModelDescriptor]) throws {
        schemaVersion = 1; self.defaultModelID = defaultModelID; self.models = models
        try validate()
    }
    public func model(id: String) -> ModelDescriptor? { models.first { $0.id == id } }

    public func validate() throws {
        func require(_ valid: Bool, _ message: String) throws {
            if !valid { throw ModelCatalogError.invalid(message) }
        }
        try require(schemaVersion == 1 && !models.isEmpty, "Unsupported or empty model catalog.")
        try require(Set(models.map(\.id)).count == models.count, "Duplicate model identity.")
        try require(model(id: defaultModelID) != nil,
                    "The default model must be present in the catalog.")
        for model in models {
            try require(model.id.range(of: "^[a-z0-9][a-z0-9-]{0,99}$", options: .regularExpression) != nil,
                        "Unsafe model identity: \(model.id)")
            try require(!model.name.isEmpty && !model.family.isEmpty && !model.license.isEmpty &&
                        !model.provenance.isEmpty && !model.compatibilityNote.isEmpty && !model.modelType.isEmpty,
                        "Missing model attribution or compatibility metadata: \(model.id)")
            if let status = model.validationStatus {
                try require(["compatible-candidate", "device-smoke-tested"].contains(status),
                            "Unknown model validation status: \(model.id)")
            }
            try require(model.chatOptions.temperature >= 0 && model.chatOptions.temperature <= 2 &&
                        model.chatOptions.topP > 0 && model.chatOptions.topP <= 1 && model.chatOptions.topK >= 0,
                        "Invalid chat options: \(model.id)")
            try require(model.repository.range(of: "^(mlx-community|lmstudio-community|prism-ml)/[A-Za-z0-9._-]+$",
                                               options: .regularExpression) != nil,
                        "Model repository is outside the curated runtime publishers: \(model.id)")
            try require(Self.hex(model.revision, count: 40), "Model revision must be immutable: \(model.id)")
            // MLX's affine_quantize rejects anything below 2 bits, and the loader
            // converts every quantized layer through it, so a 1-bit catalog entry
            // verifies perfectly and then dies on load. Keep 1 out of this list.
            try require([2, 3, 4, 5, 6, 8].contains(model.quantizationBits),
                        "Unsupported quantization: \(model.id)")
            if let path = model.bundledRelativePath {
                try require(Self.safeRelativePath(path) && path.hasPrefix("Models/"), "Unsafe bundled path.")
            }
            let names = Set(model.files.map(\.path))
            try require(!names.isEmpty && names.count == model.files.count, "Empty or duplicate model files.")
            try require(["config.json", "tokenizer.json", "tokenizer_config.json"].allSatisfy(names.contains),
                        "Missing configuration/tokenizer assets: \(model.id)")
            try require(names.contains { $0.hasSuffix(".safetensors") }, "Missing model weights: \(model.id)")
            var total: Int64 = 0
            for file in model.files {
                try require(Self.safeRelativePath(file.path), "Unsafe file path: \(file.path)")
                let suffix = URL(fileURLWithPath: file.path).pathExtension.lowercased()
                try require(["json", "safetensors", "txt", "jinja", "md", "model", ""].contains(suffix),
                            "Executable/unsupported model asset: \(file.path)")
                try require(file.size > 0 && file.size < 50_000_000_000, "Invalid model file size.")
                let validSHA = file.sha256.map { Self.hex($0, count: 64) } ?? false
                let validGit = file.gitBlobSHA.map { Self.hex($0, count: 40) } ?? false
                try require(validSHA || (validGit && file.size <= 16 * 1024 * 1024), "Missing strong file checksum.")
                if file.sha256 != nil { try require(validSHA, "Invalid SHA-256.") }
                if file.gitBlobSHA != nil { try require(validGit, "Invalid Git blob digest.") }
                let sum = total.addingReportingOverflow(file.size)
                try require(!sum.overflow, "Model size overflow."); total = sum.partialValue
            }
            try require(total == model.totalBytes, "Model byte total does not match files: \(model.id)")
        }
    }

    public static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") &&
        path.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil &&
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && !$0.hasPrefix(".") && $0 != ".."
        }
    }
    private static func hex(_ text: String, count: Int) -> Bool {
        text.count == count && text.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

public enum ModelDownloadTrust {
    public static func validate(_ url: URL) throws {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host == "huggingface.co" || host.hasSuffix(".huggingface.co") ||
              host == "cdn-lfs.hf.co" || host == "us.aws.cdn.hf.co" || host.hasSuffix(".xethub.hf.co") else {
            throw ModelCatalogError.invalid("Download destination is outside trusted HTTPS model hosts.")
        }
    }
    public static func validateResponse(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw ModelCatalogError.invalid("The model server returned an invalid response.")
        }
        try validate(url)
        guard http.statusCode == 200 else {
            throw ModelCatalogError.invalid("Model download failed with HTTP \(http.statusCode). Try again later.")
        }
    }
}
