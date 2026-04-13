import Foundation

public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var trigger: String
    public var content: String
    public var richTextData: Data?
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        trigger: String,
        content: String,
        richTextData: Data? = nil,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.trigger = trigger
        self.content = content
        self.richTextData = richTextData
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case trigger
        case content
        case richTextData
        case isEnabled
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        trigger = try container.decode(String.self, forKey: .trigger)
        content = try container.decode(String.self, forKey: .content)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public extension Snippet {
    static let sample = Snippet(
        title: "Greeting",
        trigger: "/greet",
        content: "Hi, how are you?"
    )

    var normalizedTrigger: String {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
