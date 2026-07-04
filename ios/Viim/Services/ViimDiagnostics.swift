import Foundation
import OSLog

enum ViimDiagnostics {
    private static let logger = Logger(subsystem: "com.yamstack.viim", category: "trip-pipeline")

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[Viim] \(message)")
        #endif
    }
}
