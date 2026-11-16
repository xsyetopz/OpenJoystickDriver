import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ApplicationServiceLogFollowerTests {
  private static func collect(
    _ count: Int,
    from stream: AsyncStream<ApplicationServiceLogLine>,
    while action: @Sendable () throws -> Void
  ) async throws -> [String] {
    let reader = Task { () -> [String] in
      var texts: [String] = []
      for await line in stream {
        texts.append(line.text)
        if texts.count == count { break }
      }
      return texts
    }
    try action()
    return await reader.value
  }

  private static func temporaryLog() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("service.log")
  }

  @Test
  func invalidUTF8ShowsAsReplacementCharactersNotEmptyLine() async throws {
    let url = try Self.temporaryLog()
    try Data().write(to: url)
    let stream = ApplicationServiceLogFollower.lines(of: .standardOutput, at: url, from: 0)

    let lines = try await Self.collect(1, from: stream) {
      let handle = try FileHandle(forWritingTo: url)
      handle.write(Data([0x61, 0xFF, 0x62, 0x0A]))
      handle.closeFile()
    }

    #expect(lines == ["a\u{FFFD}b"])
  }

  @Test
  func replacedFileIsReadFromItsStartEvenWhenItIsLargerThanOffset() async throws {
    let url = try Self.temporaryLog()
    try Data("old\n".utf8).write(to: url)
    let stream = ApplicationServiceLogFollower.lines(of: .standardOutput, at: url, from: 4)

    let lines = try await Self.collect(1, from: stream) {
      try FileManager.default.removeItem(at: url)
      try Data("a much longer first line of the new session\n".utf8).write(to: url)
    }

    #expect(lines == ["a much longer first line of the new session"])
  }

  @Test
  func appendedLinesAfterOffsetAreFollowed() async throws {
    let url = try Self.temporaryLog()
    try Data("before\n".utf8).write(to: url)
    let stream = ApplicationServiceLogFollower.lines(of: .standardError, at: url, from: 7)

    let lines = try await Self.collect(2, from: stream) {
      let handle = try FileHandle(forWritingTo: url)
      handle.seekToEndOfFile()
      handle.write(Data("one\ntwo\n".utf8))
      handle.closeFile()
    }

    #expect(lines == ["one", "two"])
  }
}
