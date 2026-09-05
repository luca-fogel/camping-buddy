import Foundation

public struct ReferencePassage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let keywords: [String]
    public let sourceTitle: String
    public let sourceURL: String
    public let accessedDate: String
    public let region: String
    public let rights: String
    public let reviewStatus: String
}

public struct ReferenceLibrary: Sendable {
    public let passages: [ReferencePassage]

    public init(data: Data) throws {
        passages = try JSONDecoder().decode([ReferencePassage].self, from: data)
        guard !passages.isEmpty,
              Set(passages.map(\.id)).count == passages.count,
              passages.allSatisfy({
                  $0.id.range(of: "^[a-z][a-z0-9-]+$", options: .regularExpression) != nil
                  && !$0.text.isEmpty && !$0.title.isEmpty && !$0.rights.isEmpty
                  && !$0.reviewStatus.isEmpty && !$0.accessedDate.isEmpty
                  && URL(string: $0.sourceURL)?.scheme == "https"
              }) else { throw LibraryError.invalidMetadata }
    }

    public enum LibraryError: Error { case invalidMetadata }

    /// Small deterministic lexical search. No embedding downloads or remote index.
    public func search(_ question: String, limit: Int = 3) -> [ReferencePassage] {
        let query = Self.tokens(question)
        guard !query.isEmpty, limit > 0 else { return [] }
        return passages.compactMap { passage -> (ReferencePassage, Int)? in
            let title = Self.tokens(passage.title)
            let keywords = Self.tokens(passage.keywords.joined(separator: " "))
            let body = Self.tokens(passage.text)
            let score = query.intersection(keywords).count * 4
                + query.intersection(title).count * 3 + query.intersection(body).count
            return score > 0 ? (passage, score) : nil
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    private static func tokens(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["a", "an", "the", "i", "my", "me", "we", "our", "you", "your", "is", "are", "was", "be", "to", "for", "of", "on", "in", "at", "and", "or", "with", "it", "this", "that", "do", "does", "can", "should", "would", "how", "what", "which", "when", "where", "why", "about", "some", "need", "camping", "camp", "trip", "weekend", "please"]
        let aliases = ["packing": "pack", "packed": "pack", "clothes": "clothing", "sleeping": "sleep", "meals": "meal", "maps": "map", "bears": "bear", "tents": "tent", "batteries": "battery"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !ignored.contains($0) }
            .map { aliases[$0] ?? $0 })
    }
}
