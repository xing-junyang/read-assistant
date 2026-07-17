import Foundation

// MARK: - Task Manager
/// Central manager for all reading task CRUD operations.
/// Handles persistence using NSKeyedArchiver (iOS 10 compatible).
final class TaskManager {

    // MARK: - Singleton
    static let shared = TaskManager()

    // MARK: - Properties
    private(set) var tasks: [ReadingTask] = []
    private let storageURL: URL
    private let storageQueue = DispatchQueue(label: "com.readassistant.taskmanager.storage", qos: .utility)

    // MARK: - Initialization
    private init() {
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        storageURL = URL(fileURLWithPath: docsDir).appendingPathComponent("reading_tasks.archive")
        loadTasks()
    }

    // MARK: - CRUD Operations

    /// Adds a new task and persists.
    func addTask(_ task: ReadingTask) {
        tasks.append(task)
        tasks.sort { $0.sortOrder < $1.sortOrder }
        saveTasks()
    }

    /// Removes a task by ID.
    func removeTask(withId id: String) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    /// Removes tasks at given indices.
    func removeTasks(at indices: [Int]) {
        let ids = indices.compactMap { index -> String? in
            guard index < tasks.count else { return nil }
            return tasks[index].id
        }
        tasks.removeAll { ids.contains($0.id) }
        saveTasks()
    }

    /// Updates an existing task.
    func updateTask(_ task: ReadingTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        task.modifiedAt = Date()
        tasks[index] = task
        saveTasks()
    }

    /// Duplicates a task.
    func duplicateTask(withId id: String) -> ReadingTask? {
        guard let original = tasks.first(where: { $0.id == id }) else { return nil }
        let copy = original.duplicate()
        // Insert right after the original
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks.insert(copy, at: index + 1)
        } else {
            tasks.append(copy)
        }
        saveTasks()
        return copy
    }

    /// Moves a task from one index to another (reorder).
    func moveTask(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex < tasks.count, destinationIndex < tasks.count else { return }
        let task = tasks.remove(at: sourceIndex)
        tasks.insert(task, at: destinationIndex)
        // Update sort orders
        for (i, t) in tasks.enumerated() {
            t.sortOrder = i
        }
        saveTasks()
    }

    /// Returns a task by ID.
    func task(withId id: String) -> ReadingTask? {
        return tasks.first { $0.id == id }
    }

    // MARK: - Session Management

    /// Adds a reading session to a task.
    func addSession(_ session: ReadingSession, toTaskId taskId: String) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        task.sessions.append(session)
        task.modifiedAt = Date()
        saveTasks()
    }

    // MARK: - Persistence (NSKeyedArchiver - iOS 10 compatible)

    private func saveTasks() {
        storageQueue.async { [weak self] in
            guard let self = self else { return }
            let data = NSKeyedArchiver.archivedData(withRootObject: self.tasks)
            do {
                try data.write(to: self.storageURL, options: .atomicWrite)
            } catch {
                print("[TaskManager] Failed to save tasks: \(error.localizedDescription)")
            }
        }
    }

    private func loadTasks() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            if let loaded = NSKeyedUnarchiver.unarchiveObject(with: data) as? [ReadingTask] {
                self.tasks = loaded.sorted { $0.sortOrder < $1.sortOrder }
            }
        } catch {
            print("[TaskManager] Failed to load tasks: \(error.localizedDescription)")
        }
    }
}
