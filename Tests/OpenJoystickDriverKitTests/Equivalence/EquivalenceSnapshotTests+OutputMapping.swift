import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Snapshots the virtual HID report bytes each persona produces from a fixed set of canonical
/// frames, so a change to the control-to-bit mapping shows as a snapshot difference.
///
/// Every control id of the vocabulary is driven alone: a button is pressed, a D-pad direction is
/// the hat, a stick axis goes to each extreme, and a trigger goes to its maximum. The centre is
/// the `neutral` frame, and `combined` holds several controls at once. A control whose frames
/// leave the report equal to the neutral one has no bit in that persona and is recorded as
/// `unmapped`.
struct EquivalenceSnapshotOutputMappingTests {
  typealias Encoder = (any VirtualHIDProfile, ControllerState) -> [[UInt8]]

  private struct Frame {
    let name: String
    let state: ControllerState
  }

  private static let combined = ControllerState(
    pressed: [.south, .back, .leftShoulder, .guide, .rightStickClick],
    hat: .northEast,
    leftStick: StickPosition(x: .max, y: .min),
    rightStick: StickPosition(x: .min, y: .max),
    leftTrigger: .max,
    rightTrigger: .max
  )

  private static func stickFrames(
    _ control: Control,
    left: Bool,
    xAxis: Bool
  ) -> [Frame] {
    [(BipolarValue.max, "max"), (BipolarValue.min, "min")].map { value, suffix in
      let position =
        xAxis ? StickPosition(x: value, y: .center) : StickPosition(x: .center, y: value)
      let state =
        left ? ControllerState(leftStick: position) : ControllerState(rightStick: position)
      return Frame(name: "\(control.rawValue)=\(suffix)", state: state)
    }
  }

  /// The frames that drive `control`, in a fixed order.
  private static func frames(for control: Control) -> [Frame] {
    let name = control.rawValue
    switch control {
    case .dpadUp: return [Frame(name: name, state: ControllerState(hat: .north))]
    case .dpadRight: return [Frame(name: name, state: ControllerState(hat: .east))]
    case .dpadDown: return [Frame(name: name, state: ControllerState(hat: .south))]
    case .dpadLeft: return [Frame(name: name, state: ControllerState(hat: .west))]
    case .leftTrigger:
      return [Frame(name: "\(name)=max", state: ControllerState(leftTrigger: .max))]
    case .rightTrigger:
      return [Frame(name: "\(name)=max", state: ControllerState(rightTrigger: .max))]
    case .leftStickX: return stickFrames(control, left: true, xAxis: true)
    case .leftStickY: return stickFrames(control, left: true, xAxis: false)
    case .rightStickX: return stickFrames(control, left: false, xAxis: true)
    case .rightStickY: return stickFrames(control, left: false, xAxis: false)
    default:
      return [Frame(name: name, state: ControllerState(pressed: [control]))]
    }
  }

  /// Each report as hex pairs, the reports apart by ` | `.
  private static func hex(_ reports: [[UInt8]]) -> String {
    reports.map { $0.map { unsafe String(format: "%02X", $0) }.joined(separator: " ") }
      .joined(separator: " | ")
  }

  /// One section per persona: the neutral reports, then each control's frames, with `unmapped`
  /// for a control none of whose frames change a report, then the combined frame.
  static func sections(
    encoder: Encoder? = nil
  ) -> [(title: String, lines: [String])] {
    let encoder: Encoder = encoder ?? { $0.inputReports(for: $1) }
    return VirtualHIDProfileID.allCases.map { id in
      let profile = id.makeProfile()
      let neutral = encoder(profile, .neutral)
      var lines = ["neutral: \(hex(neutral))"]
      for control in Control.allCases {
        let encoded = frames(for: control).map { ($0.name, encoder(profile, $0.state)) }
        if encoded.allSatisfy({ $0.1 == neutral }) {
          lines.append("\(control.rawValue): unmapped")
        } else {
          lines.append(contentsOf: encoded.map { "\($0.0): \(hex($0.1))" })
        }
      }
      lines.append("combined: \(hex(encoder(profile, combined)))")
      return (id.commandLineName, lines)
    }
  }

  static func rendered(encoder: Encoder? = nil) -> String {
    let header = """
      # Virtual input report bytes per persona for canonical frames, as uppercase hex pairs, each
      # input report apart by ` | `. A control whose frames leave every report equal to the
      # neutral ones is `unmapped`.

      """
    return EquivalenceSnapshotStore.render(sections(encoder: encoder), header: header)
  }

  @Test
  func outputMappingMatchesSnapshot() throws {
    let rendered = Self.rendered()
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "output-mapping.txt") == nil)
  }

  @Test
  func everyControlAndPersonaAppears() {
    let sections = Self.sections()
    let expected = VirtualHIDProfileID.allCases.map(\.commandLineName).sorted()
    #expect(sections.map(\.title).sorted() == expected)
    for section in sections {
      for control in Control.allCases {
        let present = section.lines.contains {
          $0.hasPrefix("\(control.rawValue):") || $0.hasPrefix("\(control.rawValue)=")
        }
        #expect(present, "\(section.title) omits \(control.rawValue)")
      }
    }
  }

  @Test
  func aChangedBitFailsTheComparison() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-output-mapping-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let baseline = Self.rendered()
    try Data(baseline.utf8).write(to: directory.appendingPathComponent("output-mapping.txt"))
    let same = try EquivalenceSnapshotStore.verify(
      baseline,
      named: "output-mapping.txt",
      in: directory,
      environment: [:]
    )
    #expect(same == nil)

    // Plant a one-bit change in the last byte of every report that is not neutral.
    let mutated = Self.rendered { profile, state in
      var reports = profile.inputReports(for: state)
      if state != .neutral, !reports[0].isEmpty { reports[0][reports[0].count - 1] ^= 0x01 }
      return reports
    }
    #expect(mutated != baseline)
    let result = try EquivalenceSnapshotStore.verify(
      mutated,
      named: "output-mapping.txt",
      in: directory,
      environment: [:]
    )
    #expect(result?.contains("differs from the tree") == true)
  }
}
