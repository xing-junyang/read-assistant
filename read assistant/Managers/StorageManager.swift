import Foundation
import UIKit

// MARK: - Storage Item Model
/// Represents a single storage item with its name, size, and optional detail.
struct StorageItem {
    let name: String
    let detail: String
    let sizeInBytes: Int64
}

// MARK: - Storage Category Model
/// Represents a category of storage items.
struct StorageCategory {
    let title: String
    let icon: String
    let items: [StorageItem]
    let barColor: UIColor
    
    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.sizeInBytes }
    }
}

// MARK: - Storage Manager
/// Calculates and reports storage usage across the app's data directories.
final class StorageManager {
    
    // MARK: - Singleton
    static let shared = StorageManager()
    
    private init() {}
    
    // MARK: - File Size Helpers
    
    /// Returns the size of a file at the given path, or 0 if it doesn't exist.
    private func fileSize(at path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return 0 }
        return (attrs[.size] as? Int64) ?? 0
    }
    
    /// Returns the total size of all files in a directory (non-recursive by default).
    private func directorySize(at path: String, recursive: Bool = false) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let enumerator = FileManager.default.enumerator(atPath: path)
        var total: Int64 = 0
        while let fileName = enumerator?.nextObject() as? String {
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(fileName).path
            total += fileSize(at: fullPath)
        }
        return total
    }
    
    /// Returns all file paths and their sizes in a directory.
    private func filesInDirectory(at path: String) -> [(name: String, path: String, size: Int64)] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var results: [(name: String, path: String, size: Int64)] = []
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for fileName in contents {
                let fullPath = URL(fileURLWithPath: path).appendingPathComponent(fileName).path
                let size = fileSize(at: fullPath)
                results.append((name: fileName, path: fullPath, size: size))
            }
        }
        return results.sorted { $0.size > $1.size }
    }
    
    // MARK: - Document Directory Paths
    
    private var documentsDirectory: String {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }
    
    private var cacheDirectory: String {
        NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
    }
    
    private var tempDirectory: String {
        NSTemporaryDirectory()
    }
    
    private var taskArchivePath: String {
        URL(fileURLWithPath: documentsDirectory).appendingPathComponent("reading_tasks.archive").path
    }
    
    private var audioRecordingsDirectory: String {
        URL(fileURLWithPath: documentsDirectory).appendingPathComponent("AudioRecordings").path
    }
    
    // MARK: - UserDefaults Size
    
    /// Estimates the size of UserDefaults by serializing the entire domain dictionary.
    private func userDefaultsSize() -> Int64 {
        guard let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") else {
            return 0
        }
        do {
            let data = NSKeyedArchiver.archivedData(withRootObject: domain)
            return Int64(data.count)
        } catch {
            return 0
        }
    }
    
    // MARK: - Public API
    
    /// Builds a mapping from audio file path -> (taskTitle, paragraphInfo).
    private func buildAudioPathMap() -> [String: (taskTitle: String, paragraph: String)] {
        var map: [String: (String, String)] = [:]
        let tasks = TaskManager.shared.tasks
        for task in tasks {
            for session in task.sessions {
                guard let audioPath = session.audioFilePath else { continue }
                let idx = session.expectedTextIndex
                let paragraph: String
                if idx < task.expectedTexts.count {
                    let text = task.expectedTexts[idx]
                    paragraph = text.truncated(15)
                } else {
                    paragraph = "第\(idx + 1)段"
                }
                map[audioPath] = (task.title, paragraph)
            }
        }
        return map
    }
    
    /// Returns all storage categories with their items and sizes.
    func calculateStorage() -> [StorageCategory] {
        var categories: [StorageCategory] = []
        
        // 1. Task Archive
        let archiveSize = fileSize(at: taskArchivePath)
        if archiveSize > 0 {
            let item = StorageItem(
                name: "任务存档",
                detail: "reading_tasks.archive",
                sizeInBytes: archiveSize
            )
            categories.append(StorageCategory(title: "任务数据", icon: "📋", items: [item], barColor: .primary))
        }
        
        // 2. Audio Recordings — split valid (mapped) vs orphan (no task match)
        let audioPathMap = buildAudioPathMap()
        let audioFiles = filesInDirectory(at: audioRecordingsDirectory)
        var validAudioItems: [StorageItem] = []
        var orphanAudioItems: [StorageItem] = []
        for file in audioFiles {
            if let info = audioPathMap[file.path] {
                validAudioItems.append(StorageItem(name: info.taskTitle, detail: info.paragraph, sizeInBytes: file.size))
            } else {
                orphanAudioItems.append(StorageItem(name: "无效录音", detail: file.name, sizeInBytes: file.size))
            }
        }
        if !validAudioItems.isEmpty {
            categories.append(StorageCategory(title: "录音文件", icon: "🎙", items: validAudioItems, barColor: .accent))
        }
        
        // 3. UserDefaults
        let defaultsSize = userDefaultsSize()
        if defaultsSize > 0 {
            let item = StorageItem(
                name: "应用设置",
                detail: "UserDefaults",
                sizeInBytes: defaultsSize
            )
            categories.append(StorageCategory(title: "设置数据", icon: "⚙️", items: [item], barColor: .textSecondary))
        }
        
        // 4. Cache (includes system caches, temp files, and orphan audio recordings)
        let cacheSize = directorySize(at: cacheDirectory)
        let tempSize = directorySize(at: tempDirectory)
        var cacheItems: [StorageItem] = []
        if cacheSize > 0 {
            cacheItems.append(StorageItem(name: "缓存文件", detail: "Caches", sizeInBytes: cacheSize))
        }
        if tempSize > 0 {
            cacheItems.append(StorageItem(name: "临时文件", detail: "Temp", sizeInBytes: tempSize))
        }
        // Orphan audio files (not linked to any task) go under cache
        cacheItems.append(contentsOf: orphanAudioItems)
        
        if !cacheItems.isEmpty {
            categories.append(StorageCategory(title: "缓存", icon: "🗑", items: cacheItems, barColor: .textTertiary))
        }
        
        return categories
    }
    
    /// Returns the total storage used in bytes.
    func totalStorageUsed() -> Int64 {
        calculateStorage().reduce(0) { $0 + $1.totalSize }
    }
    
    /// Clears the cache/temp directories.
    func clearCache(completion: @escaping (Bool, String) -> Void) {
        var success = true
        var message = "缓存已清除"
        
        // Clear cache directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory) {
            for item in contents {
                let path = URL(fileURLWithPath: cacheDirectory).appendingPathComponent(item).path
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    success = false
                    message = "清除缓存时发生错误"
                }
            }
        }
        
        // Clear temp directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDirectory) {
            for item in contents {
                let path = URL(fileURLWithPath: tempDirectory).appendingPathComponent(item).path
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    success = false
                    message = "清除缓存时发生错误"
                }
            }
        }
        
        // Clear orphan audio recordings (files not linked to any task)
        let audioPathMap = buildAudioPathMap()
        if let audioContents = try? FileManager.default.contentsOfDirectory(atPath: audioRecordingsDirectory) {
            for fileName in audioContents {
                let fullPath = URL(fileURLWithPath: audioRecordingsDirectory).appendingPathComponent(fileName).path
                if audioPathMap[fullPath] == nil {
                    do {
                        try FileManager.default.removeItem(atPath: fullPath)
                    } catch {
                        success = false
                        message = "清除缓存时发生错误"
                    }
                }
            }
        }
        
        completion(success, message)
    }
    
    // MARK: - Formatting
    
    /// Formats a byte count into a human-readable string.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}
