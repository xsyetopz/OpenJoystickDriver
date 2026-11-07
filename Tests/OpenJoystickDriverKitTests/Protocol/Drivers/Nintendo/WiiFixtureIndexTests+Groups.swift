import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension WiiFixtureIndexTests {
  private typealias Remote = ProtocolDescription.WiiRemote
  private static let remote = PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote

  private static let sequenceNames = [
    "handshake", "motion-plus", "motion-plus-nunchuk", "motion-plus-classic", "ir", "speaker",
  ]

  @Test
  func everyExtensionKindOfTheDescriptionHasAnIdReplyThatEqualsItsId() throws {
    let extensions = try #require(Self.remote).extensions
    let folder = WiiFixtureFolder.extensions
    for kind in extensions {
      #expect(try folder.bytes("id-\(kind.kind)") == Data(kind.id), "\(kind.kind)")
    }
  }

  @Test
  func everyExtensionDataSampleHasSixBytes() throws {
    let folder = WiiFixtureFolder.extensions
    let samples = try folder.names().filter { $0.hasPrefix("data-") }
    for kind in ["nunchuk", "classic", "motion-plus"] {
      #expect(samples.contains { $0.hasPrefix("data-\(kind)-") }, "\(kind)")
    }
    for name in ["motion-plus-slow", "motion-plus-fast"] {
      #expect(samples.contains { $0.hasPrefix("data-\(name)-") }, "\(name)")
    }
    for sample in samples {
      #expect(try folder.bytes(sample).count == 6, "\(sample)")
    }
  }

  @Test
  func everyIRFormatHasAFixtureOfItsLength() throws {
    let folder = WiiFixtureFolder.ir
    let names = try folder.names()
    for (prefix, kind) in [
      ("basic-", Remote.BlockKind.irBasic), ("extended-", .irExtended), ("full-", .irFull),
    ] {
      let matching = names.filter { $0.hasPrefix(prefix) }
      #expect(!matching.isEmpty, "\(prefix)")
      for name in matching {
        #expect(try folder.bytes(name).count == kind.lengths.lowerBound, "\(name)")
      }
    }
    for points in [0, 1, 2, 4] {
      #expect(names.contains("extended-\(points)-points"), "\(points) points")
    }
    #expect(names.contains("full-pair-a") && names.contains("full-pair-b"))
  }

  @Test
  func everySequenceHasBothRumbleVariantsThatEqualTheDescriptionScripts() throws {
    let remote = try #require(Self.remote)
    let folder = WiiFixtureFolder.sequences
    for name in Self.sequenceNames {
      for rumble in [false, true] {
        let fixture = "\(name)-rumble-\(rumble ? "on" : "off")"
        let expected = try Self.reports(name, rumble: rumble, remote: remote)
        #expect(try folder.byteStrings(fixture) == expected, "\(fixture)")
      }
    }
  }

  @Test
  func everyGroupedFixtureNamesItsSource() throws {
    for folder in [WiiFixtureFolder.extensions, .ir, .sequences] {
      for name in try folder.names() {
        let header = try folder.header(name)
        #expect(header.hasPrefix("# WiiBrew-derived (WiiBrew Wiimote"), "\(name)")
        #expect(header.contains(", revision "), "\(name)")
        #expect(header.contains("; replaced by a hardware capture at Hardware Check "), "\(name)")
      }
    }
  }

  /// The output reports of a script, built from the WiiBrew layout of reports `0x16` and `0x17`.
  private static func reports(_ name: String, rumble: Bool, remote: Remote) throws -> [Data] {
    let bit: UInt8 = rumble ? 1 << UInt8(remote.rumbleBit) : 0
    let scripts = remote.scripts
    let steps: [Remote.Step]
    var modeKey = "standalone"
    switch name {
    case "handshake": steps = scripts.handshake
    case "ir": steps = scripts.ir
    case "speaker": steps = scripts.speaker
    default:
      steps = scripts.motionPlus
      modeKey = name == "motion-plus" ? "standalone" : String(name.dropFirst("motion-plus-".count))
    }
    let level = try #require(
      remote.irSensitivityLevels.first { $0.level == remote.defaultIRSensitivityLevel }
    )
    let register: UInt8 = 0x04
    func address(_ value: UInt32) -> [UInt8] {
      [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
    func write(_ target: UInt32, _ bytes: [UInt8]) -> Data {
      let padding = [UInt8](repeating: 0, count: 16 - bytes.count)
      let header = [0x16, register | bit] + address(target) + [UInt8(bytes.count)]
      return Data(header + bytes + padding)
    }
    return try steps.map { step in
      switch step {
      case .report(let id, let data):
        return Data([id, data[0] | bit] + data.dropFirst())
      case .write(let target, let bytes):
        return write(target, bytes)
      case .read(let target, let length):
        let size = [UInt8(length >> 8), UInt8(length)]
        return Data([0x17, register | bit] + address(target) + size)
      case .sensitivity(let block, let target):
        return write(target, block == 1 ? level.block1 : level.block2)
      case .irMode(let target):
        return write(target, [try #require(remote.irModeBytes[.irExtended])])
      case .motionPlusMode(let target):
        return write(target, [try #require(remote.motionPlusModeBytes[modeKey])])
      }
    }
  }
}
