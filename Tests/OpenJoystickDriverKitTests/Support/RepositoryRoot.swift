import Foundation

enum RepositoryRoot {
  static func from(filePath: StaticString = #filePath) throws -> URL {
    var candidate = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
    let fileManager = FileManager.default

    while candidate.path != "/" {
      if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }

    throw CocoaError(.fileNoSuchFile)
  }
}
