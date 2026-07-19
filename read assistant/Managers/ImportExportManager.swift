import Foundation
import UIKit

// MARK: - Import/Export Manager
/// Handles importing and exporting reading task data to/from files.
/// Compatible with iOS 10+.
final class ImportExportManager {

    // MARK: - Singleton
    static let shared = ImportExportManager()

    private init() {}

    // MARK: - Export Text Passages (JSON format)

    /// Exports the expected texts of selected tasks to a JSON file.
    /// - Parameters:
    ///   - tasks: The tasks to export.
    ///   - completion: Called with the file URL of the exported file, or nil on failure.
    func exportTexts(tasks: [ReadingTask], completion: @escaping (URL?) -> Void) {
        var exportData: [[String: Any]] = []

        for task in tasks {
            let taskDict: [String: Any] = [
                "title": task.title,
                "description": task.detailDescription,
                "expectedTexts": task.expectedTexts
            ]
            exportData.append(taskDict)
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) else {
            completion(nil)
            return
        }

        let tempDir = NSTemporaryDirectory()
        let fileName = "reading_tasks_export_\(formattedDate()).json"
        let fileURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)

        do {
            try jsonData.write(to: fileURL, options: .atomicWrite)
            completion(fileURL)
        } catch {
            print("[ImportExportManager] Failed to write export file: \(error.localizedDescription)")
            completion(nil)
        }
    }

    // MARK: - Import Text Passages from JSON

    /// Imports tasks from a JSON file.
    /// - Parameters:
    ///   - url: The URL of the JSON file to import.
    ///   - completion: Called with the imported tasks, or nil on failure.
    func importTexts(from url: URL, completion: @escaping ([ReadingTask]?) -> Void) {
        // Access security-scoped resource
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                completion(nil)
                return
            }

            var importedTasks: [ReadingTask] = []
            let currentMaxOrder = TaskManager.shared.tasks.reduce(0) { max($0, $1.sortOrder) }

            for (index, dict) in jsonArray.enumerated() {
                guard let title = dict["title"] as? String else { continue }
                let description = dict["description"] as? String ?? ""
                let expectedTexts = dict["expectedTexts"] as? [String] ?? []

                let task = ReadingTask(
                    title: title,
                    detailDescription: description,
                    expectedTexts: expectedTexts,
                    sortOrder: currentMaxOrder + index + 1
                )
                importedTasks.append(task)
            }

            completion(importedTasks.isEmpty ? nil : importedTasks)
        } catch {
            print("[ImportExportManager] Failed to import: \(error.localizedDescription)")
            completion(nil)
        }
    }

    // MARK: - Import Text Passages from Plain Text

    /// Imports texts from a plain text file. Each non-empty line becomes a new task with one expected text,
    /// unless auto-split is enabled, in which case each newline separates expected texts in a single task.
    /// - Parameters:
    ///   - url: The URL of the text file to import.
    ///   - autoSplit: If true, splits content into separate expected texts for one task.
    ///   - completion: Called with the imported tasks, or nil on failure.
    func importTextsFromPlainText(url: URL, autoSplit: Bool, completion: @escaping ([ReadingTask]?) -> Void) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else {
                completion(nil)
                return
            }

            let currentMaxOrder = TaskManager.shared.tasks.reduce(0) { max($0, $1.sortOrder) }

            if autoSplit {
                // All lines become expected texts in one task
                let task = ReadingTask(
                    title: url.deletingPathExtension().lastPathComponent,
                    detailDescription: "从文件导入（\(lines.count)段）",
                    expectedTexts: lines,
                    sortOrder: currentMaxOrder + 1
                )
                completion([task])
            } else {
                // Each line becomes a separate task with one expected text
                var tasks: [ReadingTask] = []
                for (index, line) in lines.enumerated() {
                    let task = ReadingTask(
                        title: line.truncated(30),
                        detailDescription: "",
                        expectedTexts: [line],
                        sortOrder: currentMaxOrder + index + 1
                    )
                    tasks.append(task)
                }
                completion(tasks.isEmpty ? nil : tasks)
            }
        } catch {
            print("[ImportExportManager] Failed to import plain text: \(error.localizedDescription)")
            completion(nil)
        }
    }

    // MARK: - Export Audio Files

    /// Collects all audio files from selected tasks' sessions and copies them to a temporary directory.
    /// - Parameters:
    ///   - tasks: The tasks whose session audio files should be exported.
    ///   - completion: Called with an array of file URLs, or nil if no audio files found.
    func exportAudio(tasks: [ReadingTask], completion: @escaping ([URL]?) -> Void) {
        let exportDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audio_export_\(formattedDate())")

        // Create export directory
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            print("[ImportExportManager] Failed to create export directory: \(error.localizedDescription)")
            completion(nil)
            return
        }

        var exportedURLs: [URL] = []

        for task in tasks {
            for session in task.sessions {
                guard let audioPath = session.audioFilePath,
                      AudioRecordingManager.audioFileExists(at: audioPath) else { continue }

                let sourceURL = URL(fileURLWithPath: audioPath)
                let safeTaskName = task.title.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                let fileName = "\(safeTaskName)_session_\(session.startTime.shortChineseFormat.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")).caf"
                let destURL = exportDir.appendingPathComponent(fileName)

                do {
                    // Avoid overwriting: append a counter
                    var finalURL = destURL
                    var counter = 1
                    while FileManager.default.fileExists(atPath: finalURL.path) {
                        let nameWithoutExt = destURL.deletingPathExtension().lastPathComponent
                        let ext = destURL.pathExtension
                        finalURL = exportDir.appendingPathComponent("\(nameWithoutExt)_\(counter).\(ext)")
                        counter += 1
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: finalURL)
                    exportedURLs.append(finalURL)
                } catch {
                    print("[ImportExportManager] Failed to copy audio file: \(error.localizedDescription)")
                }
            }
        }

        completion(exportedURLs.isEmpty ? nil : exportedURLs)
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
