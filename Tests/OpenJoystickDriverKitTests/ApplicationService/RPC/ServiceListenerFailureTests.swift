import Darwin
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite(.removingTemporarySockets)
struct ServiceListenerFailureTests {
  private func plant(_ text: String, socketPath: String) throws -> String {
    let path = ServiceListenerFailure.path(forSocket: socketPath)
    try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    return path
  }

  private func problem(_ reading: ServiceListenerFailure.Reading) -> ServiceListenerFailure.Problem?
  {
    if case .unreadable(let problem) = reading { return problem }
    return nil
  }

  @Test
  func theFileRoundTripsAndNamesTheCodeTheErrnoAndTheTime() throws {
    let path = temporarySocketPath()
    let failure = ServiceListenerFailure(
      errorNumber: EMFILE,
      time: Date(timeIntervalSince1970: 1_800_000_000.7),
      process: .current
    )
    try failure.write(socketPath: path)
    defer { try? ServiceListenerFailure.clear(socketPath: path) }

    #expect(ServiceListenerFailure.read(socketPath: path) == .stopped(failure))
    let text = try String(
      contentsOfFile: ServiceListenerFailure.path(forSocket: path),
      encoding: .utf8
    )
    #expect(text.contains("\"code\" : \"E2034\""))
    #expect(text.contains("\"errno\" : \(EMFILE)"))
    #expect(text.contains("\"time\" : \"2027-01-15T08:00:00Z\""))
    let summary = failure.localizedSummary
    #expect(summary.contains("E2034"))
    #expect(summary.contains(ErrorCode.requestListenerStopped.localizedExplanation))
    #expect(summary.contains(String(EMFILE)))
  }

  @Test
  func aMissingFileIsAbsentAndClearingItIsNotAnError() throws {
    let path = temporarySocketPath()

    #expect(ServiceListenerFailure.read(socketPath: path) == .absent)
    try ServiceListenerFailure.clear(socketPath: path)
  }

  @Test
  func aMalformedFileIsAProblemNamingTheFile() throws {
    let cases = [
      "not json",
      "[]",
      "{}",
      "{\"apiVersion\":\"openjoystickdriver/v0\",\"kind\":\"ServiceListenerFailure\"}",
      "{\"apiVersion\":\"openjoystickdriver/v1alpha2\",\"kind\":\"Settings\"}",
      """
      {"apiVersion":"openjoystickdriver/v1alpha2","kind":"ServiceListenerFailure",\
      "code":"E2035","errno":9,"time":"2027-01-15T08:00:00Z","pid":1}
      """,
      """
      {"apiVersion":"openjoystickdriver/v1alpha2","kind":"ServiceListenerFailure",\
      "code":"E2034","errno":9,"time":"yesterday","pid":1}
      """,
      """
      {"apiVersion":"openjoystickdriver/v1alpha2","kind":"ServiceListenerFailure",\
      "code":"E2034","errno":9,"time":"2027-01-15T08:00:00Z","pid":1,"extra":1}
      """,
      """
      {"apiVersion":"openjoystickdriver/v1alpha2","kind":"ServiceListenerFailure",\
      "code":"E2034","errno":9,"time":"2027-01-15T08:00:00Z"}
      """,
    ]
    for text in cases {
      let socket = temporarySocketPath()
      let path = try plant(text, socketPath: socket)
      defer { try? FileManager.default.removeItem(atPath: path) }

      let found = problem(ServiceListenerFailure.read(socketPath: socket))
      #expect(found?.path == path, "\(text)")
      #expect(found?.localizedDescription.contains(path) == true)
      #expect(found?.localizedDescription.hasPrefix("E2035: ") == true)
    }
  }

  @Test
  func aFileThatIsTooLargeOrNotARegularFileIsAProblem() throws {
    let large = temporarySocketPath()
    let largePath = try plant(String(repeating: " ", count: 5000), socketPath: large)
    defer { try? FileManager.default.removeItem(atPath: largePath) }
    let target = temporarySocketPath()
    let linkPath = ServiceListenerFailure.path(forSocket: target)
    try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: largePath)
    defer { try? FileManager.default.removeItem(atPath: linkPath) }

    #expect(problem(ServiceListenerFailure.read(socketPath: large)) != nil)
    #expect(problem(ServiceListenerFailure.read(socketPath: target)) != nil)
  }

  /// The process identifier of a process that ran and ended.
  private func endedProcessIdentifier() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    return process.processIdentifier
  }

  @Test
  func aReusedIdentifierWithAnotherStartTimeIsNotTheWritingProcess() throws {
    let path = temporarySocketPath()
    let now = ServiceListenerFailure.ProcessIdentity.current
    #expect(ServiceListenerFailure.ProcessIdentity.lookup(now.identifier) == .running(now))
    let reused = ServiceListenerFailure(
      errorNumber: EBADF,
      time: Date(timeIntervalSince1970: 1_800_000_000),
      process: .init(
        identifier: now.identifier,
        startSeconds: now.startSeconds + 1,
        startMicroseconds: now.startMicroseconds
      )
    )
    try reused.write(socketPath: path)
    defer { try? ServiceListenerFailure.clear(socketPath: path) }

    #expect(
      ServiceListenerFailure.ProcessIdentity.lookup(reused.process.identifier)
        != .running(reused.process)
    )
    #expect(ServiceListenerFailure.read(socketPath: path) == .earlier(reused))
  }

  @Test
  func theFailureIsCurrentOnlyWhileTheWritingProcessRuns() throws {
    let path = temporarySocketPath()
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let running = ServiceListenerFailure(
      errorNumber: EBADF,
      time: time,
      process: .current
    )
    try running.write(socketPath: path)
    defer { try? ServiceListenerFailure.clear(socketPath: path) }
    #expect(ServiceListenerFailure.read(socketPath: path) == .stopped(running))

    let ended = ServiceListenerFailure(
      errorNumber: EBADF,
      time: time,
      process: .init(
        identifier: try endedProcessIdentifier(),
        startSeconds: 1,
        startMicroseconds: 0
      )
    )
    try ended.write(socketPath: path)
    #expect(ServiceListenerFailure.read(socketPath: path) == .earlier(ended))
    #expect(ended.localizedEarlierSummary.contains(ended.localizedSummary))
    #expect(ended.localizedEarlierSummary != ended.localizedSummary)
  }

  @Test
  func aFailedUnlinkThrowsItsOwnErrorWithTheErrno() throws {
    let socket = temporarySocketPath()
    let path = ServiceListenerFailure.path(forSocket: socket)
    // A folder with a file in it cannot be unlinked.
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    try Data().write(to: URL(fileURLWithPath: path + "/x"))
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
      try ServiceListenerFailure.clear(socketPath: socket)
      Issue.record("Expected clear to throw")
    } catch let error as ServiceListenerFailure.ClearError {
      #expect(error.path == path)
      #expect(error.errorNumber != 0)
      #expect(error.localizedDescription.contains("errno \(error.errorNumber)"))
      #expect(error.localizedDescription.contains(path))
    }
  }

  @Test
  func aRecordOfAnotherUserHasItsOwnProblem() throws {
    let socket = temporarySocketPath()
    try ServiceListenerFailure(
      errorNumber: EBADF,
      time: Date(timeIntervalSince1970: 1_800_000_000),
      process: .current
    ).write(socketPath: socket)
    defer { try? ServiceListenerFailure.clear(socketPath: socket) }

    let other = ServiceListenerFailure.read(
      socketPath: socket,
      effectiveUser: geteuid() &+ 1,
      lookup: ServiceListenerFailure.ProcessIdentity.lookup
    )
    let found = problem(other)
    #expect(found?.detail == Localization().string("status.listenerFailure.otherUser"))
    #expect(found?.detail != Localization().string("status.listenerFailure.notRegularFile"))
    #expect(problem(ServiceListenerFailure.read(socketPath: socket)) == nil)
  }

  @Test
  func aLookupThatFailsNamesWhySoAProcessOfAnotherUserIsNotTheWriter() {
    typealias Lookup = ServiceListenerFailure.ProcessIdentity.Lookup
    #expect(Lookup.failed(with: ESRCH) == .noSuchProcess)
    #expect(Lookup.failed(with: EPERM) == .belongsToAnotherUser)
    #expect(Lookup.failed(with: EINVAL) == .unknown(EINVAL))
    #expect(
      ServiceListenerFailure.ProcessIdentity.lookup(getpid())
        == .running(.current)
    )
  }

  @Test(.enabled(if: geteuid() != 0, "root may inspect every process"))
  func theSystemProcessOfAnotherUserBelongsToAnotherUser() {
    // launchd (pid 1) belongs to root, so a user that is not root gets EPERM.
    #expect(ServiceListenerFailure.ProcessIdentity.lookup(1) == .belongsToAnotherUser)
  }

  @Test
  func aLookupThatFailsForAnotherReasonIsReportedNotGuessed() throws {
    let socket = temporarySocketPath()
    let failure = ServiceListenerFailure(
      errorNumber: EBADF,
      time: Date(timeIntervalSince1970: 1_800_000_000),
      process: .current
    )
    try failure.write(socketPath: socket)
    defer { try? ServiceListenerFailure.clear(socketPath: socket) }

    let reading = ServiceListenerFailure.read(
      socketPath: socket,
      effectiveUser: geteuid()
    ) { _ in .unknown(EINVAL) }

    let found = problem(reading)
    #expect(found?.path == ServiceListenerFailure.path(forSocket: socket))
    #expect(found?.detail.contains(String(cString: strerror(EINVAL))) == true)
    #expect(
      found?.detail.contains("errno") == true || found?.detail.contains(String(EINVAL)) == true
    )
    #expect(found?.localizedDescription.hasPrefix("E2035: ") == true)
    // The same record is current or earlier when the lookup answers.
    let running = ServiceListenerFailure.read(
      socketPath: socket,
      effectiveUser: geteuid()
    ) { _ in .running(failure.process) }
    #expect(running == .stopped(failure))
    let gone = ServiceListenerFailure.read(
      socketPath: socket,
      effectiveUser: geteuid()
    ) { _ in .belongsToAnotherUser }
    #expect(gone == .earlier(failure))
  }
}
