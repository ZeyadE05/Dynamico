import Foundation
import AppKit
import Combine

@MainActor
public final class FileShelfManager: ObservableObject {
    public static let shared = FileShelfManager()

    @Published public var stagedFiles: [StagedFile] = []
    
    private let shelfTempDirectory: URL

    private init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DynamicoStagedFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.shelfTempDirectory = tempDir
    }

    public func stageFiles(from urls: [URL]) {
        for url in urls {
            // Check if file already staged
            if stagedFiles.contains(where: { $0.url == url }) {
                continue
            }

            // Create a copy in temp directory if needed, or reference directly
            let destinationURL = shelfTempDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destinationURL)
            
            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
                let item = StagedFile(url: destinationURL)
                self.stagedFiles.append(item)
            } catch {
                // Fallback to original URL reference if copy fails
                let item = StagedFile(url: url)
                self.stagedFiles.append(item)
            }
        }
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    public func removeFile(_ item: StagedFile) {
        stagedFiles.removeAll(where: { $0.id == item.id })
        try? FileManager.default.removeItem(at: item.url)
    }

    public func clearAll() {
        for file in stagedFiles {
            try? FileManager.default.removeItem(at: file.url)
        }
        stagedFiles.removeAll()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
