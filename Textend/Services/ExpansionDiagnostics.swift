import OSLog

enum ExpansionDiagnostics {
  private static let logger = Logger(subsystem: BuildIdentity.bundleID, category: "Expansion")

  /// Persist fixed reasons and process IDs in release builds too, never input text.
  static func record(_ reason: String, processID: Int32) {
    logger.notice("\(reason, privacy: .public); pid=\(processID)")
  }
}
