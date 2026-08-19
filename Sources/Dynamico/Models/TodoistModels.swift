import Foundation

public struct TodoistDue: Codable, Equatable, Sendable {
    public let date: String?
    public let string: String?
    public let isRecurring: Bool?
    public let datetime: String?

    enum CodingKeys: String, CodingKey {
        case date
        case string
        case isRecurring = "is_recurring"
        case datetime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try? container.decodeIfPresent(String.self, forKey: .date)
        self.string = try? container.decodeIfPresent(String.self, forKey: .string)
        self.isRecurring = try? container.decodeIfPresent(Bool.self, forKey: .isRecurring)
        self.datetime = try? container.decodeIfPresent(String.self, forKey: .datetime)
    }

    public init(date: String? = nil, string: String? = nil, isRecurring: Bool? = nil, datetime: String? = nil) {
        self.date = date
        self.string = string
        self.isRecurring = isRecurring
        self.datetime = datetime
    }
}

public struct TodoistTask: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let content: String
    public let description: String?
    public let isCompleted: Bool?
    public let priority: Int?
    public let due: TodoistDue?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case description
        case isCompleted = "is_completed"
        case priority
        case due
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let stringId = try? container.decode(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decode(Int64.self, forKey: .id) {
            self.id = String(intId)
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = UUID().uuidString
        }

        self.content = (try? container.decodeIfPresent(String.self, forKey: .content)) ?? ""
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.isCompleted = try? container.decodeIfPresent(Bool.self, forKey: .isCompleted)
        self.priority = try? container.decodeIfPresent(Int.self, forKey: .priority)
        self.due = try? container.decodeIfPresent(TodoistDue.self, forKey: .due)
        self.url = try? container.decodeIfPresent(String.self, forKey: .url)
    }

    public init(id: String, content: String, description: String? = nil, isCompleted: Bool? = nil, priority: Int? = nil, due: TodoistDue? = nil, url: String? = nil) {
        self.id = id
        self.content = content
        self.description = description
        self.isCompleted = isCompleted
        self.priority = priority
        self.due = due
        self.url = url
    }
}

public struct TodoistTaskResponseWrapper: Codable, Sendable {
    public let tasks: [TodoistTask]?
    public let results: [TodoistTask]?
    public let items: [TodoistTask]?
}

public struct CreateTodoistTaskPayload: Encodable, Sendable {
    public let content: String
    public let description: String?

    public init(content: String, description: String? = nil) {
        self.content = content
        self.description = description
    }
}
