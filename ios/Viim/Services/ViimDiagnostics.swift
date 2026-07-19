import Foundation
import OSLog

enum ViimDiagnostics {
    private static let logger = Logger(subsystem: "com.yamstack.viim", category: "trip-pipeline")
    private static let ioQueue = DispatchQueue(label: "com.yamstack.viim.diagnostics")
    private static let maxLogBytes = 256_000

    static func logBuildIdentity(bundle: Bundle = .main) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let gitSHA = bundle.object(forInfoDictionaryKey: "VIIMGitSHA") as? String ?? "unknown"
        let buildDate = bundle.object(forInfoDictionaryKey: "VIIMBuildDate") as? String ?? "unknown"
        log("app.launch version=\(version) build=\(build) sha=\(gitSHA) builtAt=\(buildDate)")
    }

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        appendToDisk(message)
        #if DEBUG
        print("[Viim] \(message)")
        #endif
    }

    private static func appendToDisk(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"

        ioQueue.async {
            guard let data = line.data(using: .utf8),
                  let url = diagnosticsLogURL() else {
                return
            }

            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fileManager.fileExists(atPath: url.path) {
                    _ = fileManager.createFile(atPath: url.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
                trimIfNeeded(url: url)
            } catch {
                logger.error("diagnostics.disk.write.failed")
            }
        }
    }

    private static func diagnosticsLogURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ViimDiagnostics.log")
    }

    private static func trimIfNeeded(url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? NSNumber
            guard size?.intValue ?? 0 > maxLogBytes else {
                return
            }

            let data = try Data(contentsOf: url)
            let trimmed = Data(data.suffix(maxLogBytes / 2))
            try trimmed.write(to: url, options: .atomic)
        } catch {
            logger.error("diagnostics.disk.trim.failed")
        }
    }
}
