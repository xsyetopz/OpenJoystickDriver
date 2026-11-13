import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct HIDInputReportQueueTests {
  /// The DualShock 3 sends 49-byte reports: 1,024 entries of 81 bytes use 82,944 of the 131,072
  /// bytes, five times the 16,384 bytes of the default queue.
  @Test
  func dualShockReportGetsTargetCountWithinKernelLimit() throws {
    let sizing = try #require(HIDInputReportQueue.sizing(maxInputReportSize: 49))

    #expect(sizing.entrySize == 49 + HIDInputReportQueue.entryOverheadBytes)
    #expect(sizing.reportCount == HIDInputReportQueue.targetReportCount)
    #expect(sizing.entrySize * sizing.reportCount <= HIDInputReportQueue.maximumBytes)
  }

  @Test
  func largeReportShrinksCountToStayWithinKernelLimit() throws {
    let sizing = try #require(HIDInputReportQueue.sizing(maxInputReportSize: 512))

    #expect(sizing.reportCount < HIDInputReportQueue.targetReportCount)
    #expect(sizing.entrySize * sizing.reportCount <= HIDInputReportQueue.maximumBytes)
  }

  @Test
  func entryOverKernelLimitHasNoSizing() {
    #expect(HIDInputReportQueue.sizing(maxInputReportSize: 8_200) == nil)
  }

  @Test
  func emptyReportSizeStillHoldsOneByte() throws {
    let sizing = try #require(HIDInputReportQueue.sizing(maxInputReportSize: 0))

    #expect(sizing.entrySize == 1 + HIDInputReportQueue.entryOverheadBytes)
  }

  /// The `DebugState` of an `IOHIDLibUserClient` as `ioreg` prints it.
  @Test
  func dropCountIsEnqueueErrorCountOfEventQueues() {
    let properties: [String: Any] = [
      "DebugState": [
        "ClientSeized": false,
        "EventQueueMap": [
          ["QueueSize": 16_384, "EnqueueErrorCount": 458, "head": 13_604],
          ["QueueSize": 16_384, "EnqueueErrorCount": 2],
        ],
      ] as [String: Any]
    ]

    #expect(HIDInputReportDrops.droppedReports(inClientProperties: properties) == 460)
  }

  @Test
  func clientWithoutQueueMapHasNoDropCount() {
    #expect(HIDInputReportDrops.droppedReports(inClientProperties: [:]) == nil)
    #expect(
      HIDInputReportDrops.droppedReports(inClientProperties: ["DebugState": ["EventQueueMap": []]])
        == 0
    )
    #expect(
      HIDInputReportDrops.droppedReports(inClientProperties: ["DebugState": ["x": 1]]) == nil
    )
  }

  @Test
  func creatorNamesProcessByIdentifier() {
    #expect(HIDInputReportDrops.creator("pid 51958, OpenJoystickDriv", isProcess: 51958))
    #expect(!HIDInputReportDrops.creator("pid 519580, steam_osx", isProcess: 51958))
  }
}
