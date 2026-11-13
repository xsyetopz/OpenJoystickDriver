import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Pins the `HIDDescriptor` usage tables to the output the coded tables produced.
///
/// `Tests/HIDUsageGolden/hid-usage-layouts.txt` was rendered by the driver before its tables moved
/// into records. These samples are hand-written element values, not hardware captures: every button
/// usage, every Generic Desktop axis and hat value, and the Simulation and Consumer usages the
/// tables name, each fed to every layout over several logical ranges and both with and without a
/// report ID. The golden holds one line per step, so a changed table names the step that moved.
struct HIDUsageLayoutEquivalenceTests {
  private typealias Parse = DriverParseCharacterizationTests

  /// Usage Page (Generic Desktop), Usage (Game Pad), Collection (Application), Z and Rz, then
  /// Simulation Controls Brake and Accelerator, then Consumer Record.
  static let zRzBrakeDescriptor = Data([
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x00,
    0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0x05, 0x02, 0x09, 0xC5, 0x09, 0xC4, 0x15, 0x00, 0x26,
    0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0x05, 0x0C, 0x09, 0xB2, 0x15, 0x00, 0x25,
    0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0xC0,
  ])

  /// The same, with Rx and Ry added: not the Z/Rz shape.
  static let rxRyDescriptor = Data([
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x09, 0x32, 0x09, 0x33, 0x09, 0x34, 0x09, 0x35, 0x15,
    0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02, 0x05, 0x02, 0x09, 0xC5, 0x09,
    0xC4, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0xC0,
  ])

  /// Each layout comes from the record or description that declares it.
  private func drivers() throws -> [(name: String, driver: HIDDescriptorDriver)] {
    let model = ControllerModelID(vendorID: 0xFFFE, productID: 1)
    return [
      ("standard", HIDDescriptorDriver(model: model)),
      ("Wr007", HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x11C1, 0x5600))),
      (
        "ScufEnvision",
        HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x2E95, 0x434D))
      ),
      (
        "ZRzBrakeLeft",
        HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x2DC8, 0x301D))
      ),
      (
        "DragonRise",
        HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x0079, 6))
      ),
      (
        "descriptor Z/Rz Brake Record",
        HIDDescriptorDriver(model: model, reportDescriptor: Self.zRzBrakeDescriptor)
      ),
      (
        "descriptor Rx Ry",
        HIDDescriptorDriver(model: model, reportDescriptor: Self.rxRyDescriptor)
      ),
    ] + (try Self.halfAndButtonMaps()).map { ($0, HIDDescriptorDriver(model: model, usageMap: $1)) }
  }

  /// One map per kind that binds part of an element: a combined trigger axis on Z, D-pad
  /// directions on X, buttons on Rz, and a button that reads as a trigger.
  private static func halfAndButtonMaps() throws -> [(String, HIDUsageMap)] {
    func usage(_ number: Int, page: Int = 0x01) -> HIDUsage {
      HIDUsage(usagePage: page, usage: number)
    }
    func entry(_ usage: HIDUsage, _ binding: HIDUsageMap.Binding) -> HIDUsageMap.Entry {
      .init(usage: usage, binding: binding)
    }
    func half(
      _ half: HIDUsageMap.Half,
      _ control: Control,
      _ threshold: Float
    ) -> HIDUsageMap.Binding {
      .axisButton(.init(half: half, control: control, threshold: threshold))
    }
    return [
      (
        "HalfAxis Z",
        try HIDUsageMap(entries: [
          entry(
            usage(0x32),
            .halfAxis(.init(half: .positive, control: .leftTrigger, isInverted: false))
          ),
          entry(
            usage(0x32),
            .halfAxis(.init(half: .negative, control: .rightTrigger, isInverted: true))
          ),
        ])
      ),
      (
        "AxisDpad X",
        try HIDUsageMap(entries: [
          entry(
            usage(0x30),
            .axisDpad(.init(half: .negative, control: .dpadLeft, threshold: 0.5))
          ),
          entry(
            usage(0x30),
            .axisDpad(.init(half: .positive, control: .dpadRight, threshold: 0.5))
          ),
        ])
      ),
      (
        "AxisButton Rz",
        try HIDUsageMap(entries: [
          entry(usage(0x35), half(.positive, .east, 0.5)),
          entry(usage(0x35), half(.negative, .west, 0.75)),
        ])
      ),
      (
        "ButtonTrigger 7",
        try HIDUsageMap(entries: [
          entry(usage(7, page: 0x09), .buttonTrigger(.rightTrigger))
        ])
      ),
    ]
  }

  private static func steps() -> [Parse.Step] {
    func element(
      _ page: UInt32,
      _ usage: UInt32,
      _ value: Int,
      range: ClosedRange<Int>,
      reportID: UInt32?
    ) -> HIDElementValue {
      HIDElementValue(
        usagePage: page,
        usage: usage,
        logicalMinimum: range.lowerBound,
        logicalMaximum: range.upperBound,
        integerValue: value,
        reportID: reportID
      )
    }
    var steps: [Parse.Step] = []
    for reportID: UInt32? in [nil, 6] {
      let tag = reportID.map { "r\($0)" } ?? "r-"
      func add(_ page: UInt32, _ usage: UInt32, _ values: [Int], _ range: ClosedRange<Int>) {
        for value in values {
          let label = "\(tag) p\(page)u\(String(usage, radix: 16))"
          steps.append(
            Parse.Step(
              "\(label)[\(range.lowerBound)...\(range.upperBound)]=\(value)",
              element: element(page, usage, value, range: range, reportID: reportID)
            )
          )
        }
      }
      for usage in UInt32(1)...20 {
        add(0x09, usage, [1, 0], 0...1)
      }
      for usage in UInt32(0x30)...0x36 {
        add(0x01, usage, [0, 128, 255, 77], 0...255)
        add(0x01, usage, [-32_768, 0, 32_767], -32_768...32_767)
        add(0x01, usage, [1_023, 512], 0...1_023)
        add(0x01, usage, [5], 0...0)
      }
      add(0x01, 0x39, Array(0...8) + [15], 0...7)
      add(0x01, 0x39, [1, 5, 8, 9], 1...8)
      add(0x01, 0x85, [1, 0], 0...1)
      for usage in [UInt32(0xC4), 0xC5] {
        add(0x02, usage, [0, 128, 255], 0...255)
        add(0x02, usage, [-32_768, 32_767], -32_768...32_767)
      }
      for usage in [UInt32(0xB2), 0x223, 0x224] {
        add(0x0C, usage, [1, 0], 0...1)
      }
      add(0x07, 0x04, [1], 0...1)
    }
    return steps
  }

  private func render() throws -> String {
    let parse = Parse()
    let steps = Self.steps()
    return try drivers().map { name, driver in
      let controls = driver.capabilities.controls.map { "\($0)" }.sorted().joined(separator: ",")
      let lines =
        ["capabilities [\(controls)]"]
        + parse.transcript(driver, steps)
      return "## \(name)\n" + lines.joined(separator: "\n") + "\n"
    }.joined(separator: "\n")
  }

  @Test
  func everyUsageTableMatchesCodedOutput() throws {
    let rendered = try render()
    let file = EquivalenceSnapshotStore.directory.deletingLastPathComponent()
      .appendingPathComponent("HIDUsageGolden/hid-usage-layouts.txt")
    let expected = try String(contentsOf: file, encoding: .utf8)
    let actualLines = rendered.split(separator: "\n", omittingEmptySubsequences: false)
    let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(actualLines.count == expectedLines.count)
    for (index, pair) in zip(actualLines, expectedLines).enumerated() where pair.0 != pair.1 {
      Issue.record("line \(index + 1): \(pair.0) != \(pair.1)")
      break
    }
  }
}
