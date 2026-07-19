import SwifterKit

actor OpenJoystickRelayDriver: SwiftDriver, DriverKitRelaySubmitting {
  static let configuration = OpenJoystickDriverRelayConfiguration.driver

  private var context: DriverContext?

  func start(context: DriverContext) async throws {
    await Task.yield()
    try context.require(.hid)
    self.context = context
  }

  func handle(event: DriverEvent, context: DriverContext) async throws {
    guard let report = try event.hidReport(), let input = Self.forwardedInput(for: report) else {
      return
    }
    try await context.submitHIDInputReport(input)
  }

  func stop(context: DriverContext) async {
    await Task.yield()
    self.context = nil
  }

  func submit(_ report: HIDReport) async throws {
    guard let context else { throw DriverContextError.notConnected }
    try await context.submitHIDInputReport(report)
  }

  func statistics() async throws -> HIDRuntimeStatistics {
    guard let context else { throw DriverContextError.notConnected }
    return try await context.hidRuntimeStatistics()
  }

  static func forwardedInput(for report: HIDReport) -> HIDReport? {
    guard report.type == .output else { return nil }
    let magic: [UInt8] = [0x4F, 0x4A]
    if report.bytes.starts(with: magic) {
      guard report.bytes.count > 3 else { return nil }
      return HIDReport(
        bytes: Array(report.bytes.dropFirst(3)),
        type: .input,
        options: UInt32(report.bytes[2]),
        timestamp: report.timestamp
      )
    }
    guard !report.bytes.isEmpty else { return nil }
    return HIDReport(
      bytes: report.bytes,
      type: .input,
      options: report.options,
      timestamp: report.timestamp
    )
  }
}
