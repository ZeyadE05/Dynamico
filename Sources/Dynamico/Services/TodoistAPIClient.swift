import Foundation
import Combine
import AppKit

@MainActor
public final class TodoistAPIClient: ObservableObject {
    public static let shared = TodoistAPIClient()

    private let keychainKey = "todoist_api_token"

    @Published public var tasks: [TodoistTask] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var isAuthenticated: Bool = false
    @Published public var apiToken: String = ""

    private init() {
        if let storedToken = KeychainHelper.shared.read(forKey: keychainKey), !storedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.apiToken = storedToken
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = false
        }
    }

    public func saveToken(_ token: String) async -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            disconnect()
            return false
        }

        let success = KeychainHelper.shared.save(trimmedToken, forKey: keychainKey)
        if success {
            self.apiToken = trimmedToken
            self.isAuthenticated = true
            return await fetchTasks()
        } else {
            self.errorMessage = "Failed to save API token to Keychain."
            return false
        }
    }

    public func disconnect() {
        KeychainHelper.shared.delete(forKey: keychainKey)
        self.apiToken = ""
        self.isAuthenticated = false
        self.tasks = []
        self.errorMessage = nil
    }

    @discardableResult
    public func fetchTasks() async -> Bool {
        guard !apiToken.isEmpty else {
            self.isAuthenticated = false
            self.tasks = []
            return false
        }

        self.isLoading = true
        defer { self.isLoading = false }

        guard let url = URL(string: "https://api.todoist.com/api/v1/tasks") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                self.errorMessage = "Invalid network response."
                return false
            }

            if httpResponse.statusCode == 401 {
                self.isAuthenticated = false
                self.errorMessage = "Invalid API token. Please check your settings."
                return false
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                self.errorMessage = "HTTP Error \(httpResponse.statusCode)"
                return false
            }

            if let fetchedTasks = try? JSONDecoder().decode([TodoistTask].self, from: data) {
                self.tasks = fetchedTasks
            } else if let wrapper = try? JSONDecoder().decode(TodoistTaskResponseWrapper.self, from: data) {
                self.tasks = wrapper.tasks ?? wrapper.results ?? wrapper.items ?? []
            } else {
                do {
                    let fetchedTasks = try JSONDecoder().decode([TodoistTask].self, from: data)
                    self.tasks = fetchedTasks
                } catch {
                    print("Todoist JSON decoding error: \(error)")
                    if let rawString = String(data: data, encoding: .utf8) {
                        print("Raw JSON response: \(rawString.prefix(400))")
                    }
                    self.errorMessage = "Data format error: \(error.localizedDescription)"
                    return false
                }
            }

            self.isAuthenticated = true
            self.errorMessage = nil
            return true
        } catch {
            self.errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            print("Todoist API fetch error: \(error)")
            return false
        }
    }

    public func completeTask(id: String) async {
        guard isAuthenticated, !apiToken.isEmpty else { return }

        // Optimistically remove task from list for instant UI feedback
        let originalTasks = self.tasks
        self.tasks.removeAll { $0.id == id }

        guard let url = URL(string: "https://api.todoist.com/api/v1/tasks/\(id)/close") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                // Revert on failure
                self.tasks = originalTasks
                self.errorMessage = "Failed to complete task."
            }
        } catch {
            self.tasks = originalTasks
            self.errorMessage = "Network error completing task."
        }
    }

    public func addTask(content: String) async -> Bool {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty, isAuthenticated, !apiToken.isEmpty else { return false }

        guard let url = URL(string: "https://api.todoist.com/api/v1/tasks") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateTodoistTaskPayload(content: trimmedContent)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                self.errorMessage = "Failed to create task."
                return false
            }

            let newTask = try JSONDecoder().decode(TodoistTask.self, from: data)
            self.tasks.insert(newTask, at: 0)
            self.errorMessage = nil
            return true
        } catch {
            self.errorMessage = "Error creating task."
            return false
        }
    }
}
