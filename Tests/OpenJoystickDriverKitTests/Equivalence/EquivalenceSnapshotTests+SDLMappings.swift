import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Snapshots the SDL mapping text each virtual HID profile yields.
///
/// The mapping is derived by `VirtualHIDProfileID.gamepadMapping()`, which the CLI also prints, so
/// this snapshot pins what ships. It lists each probe so a changed report shows where it moved.
struct EquivalenceSnapshotSDLMappingTests {
  private static func section(
    for id: VirtualHIDProfileID
  ) throws -> (
    title: String, lines: [String]
  ) {
    let profile = id.makeProfile()
    let mapping = try id.gamepadMapping()
    let identity = profile.identity
    var lines = [
      "profile=\(id.rawValue) vendor=\(identity.vendorID) product=\(identity.productID)"
        + " version=\(identity.versionNumber) name=\(identity.productName)",
      "guid=\(mapping.guid)",
      "report length=\(profile.inputReport(for: .neutral).count)"
        + " descriptorBytes=\(profile.descriptor.count)",
    ]
    for probe in mapping.probes {
      lines.append(
        "probe \(probe.control.rawValue) fields=[\(probe.fields.joined(separator: "+"))]"
          + " -> \(probe.binding ?? "none")"
      )
    }
    lines.append("mapping=\(mapping.sdlMapping)")
    lines.append("unmapped=\(mapping.unmapped.map(\.rawValue).joined(separator: ","))")
    return (id.rawValue, lines)
  }

  @Test
  func sdlMappingsMatchSnapshot() throws {
    let sections = try VirtualHIDProfileID.allCases.map(Self.section)
    let header = """
      # The SDL mapping each virtual HID profile derives for itself. Each line is derived by
      # driving one control through the profile's report codec and reading the HID fields it
      # changes. Entries follow SDL's field order; analog triggers carry the + half-axis prefix
      # SDL expects for 0..max axes.

      """
    let rendered = EquivalenceSnapshotStore.render(sections, header: header)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "sdl-mappings.txt") == nil)
  }
}
