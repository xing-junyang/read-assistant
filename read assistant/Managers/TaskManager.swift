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

    /// Removes a task by ID, cleaning up all associated audio files.
    /// Built-in tasks cannot be removed.
    func removeTask(withId id: String) {
        guard let task = tasks.first(where: { $0.id == id }), !task.isBuiltIn else { return }
        // Clean up audio files for all sessions
        for session in task.sessions {
            if let audioPath = session.audioFilePath {
                AudioRecordingManager.deleteAudioFile(at: audioPath)
            }
        }
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    /// Removes tasks at given indices, cleaning up audio files.
    /// Built-in tasks are skipped.
    func removeTasks(at indices: [Int]) {
        let ids = indices.compactMap { index -> String? in
            guard index < tasks.count else { return nil }
            let task = tasks[index]
            return task.isBuiltIn ? nil : task.id
        }
        // Clean up audio files for all sessions in removed tasks
        for id in ids {
            if let task = tasks.first(where: { $0.id == id }) {
                for session in task.sessions {
                    if let audioPath = session.audioFilePath {
                        AudioRecordingManager.deleteAudioFile(at: audioPath)
                    }
                }
            }
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

    /// Duplicates a task. Built-in tasks cannot be duplicated.
    func duplicateTask(withId id: String) -> ReadingTask? {
        guard let original = tasks.first(where: { $0.id == id }),
              !original.isBuiltIn else { return nil }
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

    /// Removes a reading session from a task and deletes its associated audio file.
    func removeSession(_ session: ReadingSession, fromTaskId taskId: String) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }

        // Delete the audio file if it exists
        if let audioPath = session.audioFilePath {
            AudioRecordingManager.deleteAudioFile(at: audioPath)
        }

        task.sessions.removeAll { $0.id == session.id }
        task.modifiedAt = Date()
        saveTasks()
    }

    /// Removes sessions at given indices from a task, cleaning up audio files.
    func removeSessions(at indices: [Int], fromTaskId taskId: String) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        let sortedIndices = indices.sorted(by: >)
        for index in sortedIndices {
            guard index < task.sessions.count else { continue }
            let session = task.sessions[index]

            // Delete the audio file if it exists
            if let audioPath = session.audioFilePath {
                AudioRecordingManager.deleteAudioFile(at: audioPath)
            }

            task.sessions.remove(at: index)
        }
        task.modifiedAt = Date()
        saveTasks()
    }

    // MARK: - Built-in Tasks

    /// Ensures all built-in tasks exist in the task list.
    /// Called after loading saved tasks to add any missing built-in tasks.
    private func ensureBuiltInTasks() {
        let existingIDs = Set(tasks.map { $0.id })
        var needsSave = false

        for builtInTask in BuiltInTasks.allTasks {
            if !existingIDs.contains(builtInTask.id) {
                tasks.append(builtInTask)
                needsSave = true
            }
        }

        if needsSave {
            tasks.sort { $0.sortOrder < $1.sortOrder }
            saveTasks()
        }
    }

    /// Returns whether a task can be deleted by the user.
    func canDelete(task: ReadingTask) -> Bool {
        return !task.isBuiltIn
    }

    /// Returns whether a task can be duplicated by the user.
    func canDuplicate(task: ReadingTask) -> Bool {
        return !task.isBuiltIn
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
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                let data = try Data(contentsOf: storageURL)
                if let loaded = NSKeyedUnarchiver.unarchiveObject(with: data) as? [ReadingTask] {
                    self.tasks = loaded.sorted { $0.sortOrder < $1.sortOrder }
                }
            } catch {
                print("[TaskManager] Failed to load tasks: \(error.localizedDescription)")
            }
        }
        // Always ensure built-in tasks exist after loading
        ensureBuiltInTasks()
    }
}
