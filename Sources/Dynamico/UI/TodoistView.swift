import SwiftUI
import AppKit

public struct TodoistView: View {
    @ObservedObject var todoist = TodoistAPIClient.shared
    @State private var newTaskTitle: String = ""
    @State private var isSubmitting: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Text("Todoist")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))

                    if todoist.isAuthenticated && !todoist.tasks.isEmpty {
                        Text("\(todoist.tasks.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 228/255, green: 71/255, blue: 62/255).opacity(0.25)))
                            .foregroundColor(Color(red: 255/255, green: 110/255, blue: 100/255))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if todoist.isAuthenticated {
                        Button(action: {
                            Task {
                                await todoist.fetchTasks()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh tasks")

                        Button(action: {
                            if let url = URL(string: "https://todoist.com/app") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text("Open Todoist")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if !todoist.isAuthenticated {
                unauthenticatedState
            } else if todoist.isLoading && todoist.tasks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
            } else if todoist.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }

            if todoist.isAuthenticated {
                quickAddBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if todoist.isAuthenticated && todoist.tasks.isEmpty {
                Task {
                    await todoist.fetchTasks()
                }
            }
        }
    }

    private var unauthenticatedState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.system(size: 22))
                .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255).opacity(0.85))

            Text("Connect Todoist")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.white.opacity(0.9))

            HStack(spacing: 6) {
                Button(action: {
                    if let url = URL(string: "https://todoist.com/app/settings/integrations") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill")
                        Text("Get My API Token")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 228/255, green: 71/255, blue: 62/255).opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Opens Todoist settings page where your API token is located at the bottom")
            }

            HStack(spacing: 6) {
                SecureField("Paste API Token here...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .frame(maxWidth: 240)

                Button(action: {
                    let token = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { return }
                    Task {
                        let success = await todoist.saveToken(token)
                        if success {
                            newTaskTitle = ""
                        }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                        Text("Connect")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 228/255, green: 71/255, blue: 62/255))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 2)

            if let error = todoist.errorMessage {
                Text(error)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Color.green.opacity(0.7))

            Text("All Caught Up!")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.75))

            Text("No active tasks in your Todoist inbox.")
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.4))

            Spacer()
        }
    }

    private var taskList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(todoist.tasks) { task in
                    taskRow(task)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
    }

    private func taskRow(_ task: TodoistTask) -> some View {
        HStack(spacing: 8) {
            // Checkbox to complete task
            Button(action: {
                Task {
                    await todoist.completeTask(id: task.id)
                }
            }) {
                Image(systemName: "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(priorityColor(task.priority))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            // Task Content
            VStack(alignment: .leading, spacing: 2) {
                Text(task.content)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineLimit(1)

                if let due = task.due, let label = due.string ?? due.date {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text(label)
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255).opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            // Optional direct task web URL link
            if let rawUrl = task.url, let taskUrl = URL(string: rawUrl) {
                Button(action: {
                    NSWorkspace.shared.open(taskUrl)
                }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var quickAddBar: some View {
        HStack(spacing: 6) {
            TextField("Add task to Todoist...", text: $newTaskTitle, onCommit: {
                submitNewTask()
            })
            .textFieldStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))

            Button(action: {
                submitNewTask()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color(red: 228/255, green: 71/255, blue: 62/255))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            .opacity(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        Task {
            let success = await todoist.addTask(content: title)
            if success {
                newTaskTitle = ""
            }
            isSubmitting = false
        }
    }

    private func priorityColor(_ priority: Int?) -> Color {
        guard let p = priority else { return Color.white.opacity(0.4) }
        switch p {
        case 4: return Color(red: 228/255, green: 71/255, blue: 62/255) // Todoist p1 (Urgent Red)
        case 3: return Color.orange // Todoist p2 (Orange)
        case 2: return Color.blue // Todoist p3 (Blue)
        default: return Color.white.opacity(0.45) // Todoist p4 (Normal/Clear)
        }
    }
}
