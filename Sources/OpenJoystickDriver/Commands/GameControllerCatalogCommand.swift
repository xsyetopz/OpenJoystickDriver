import Foundation
import OpenJoystickDriverKit

struct GameControllerCatalogCommand {
  private struct JSONOutput: Codable {
    let audit: AppleGameControllerSupportAudit
    let appleEntries: [AppleGameControllerCatalogEntry]?
  }

  func run(arguments: [String]) {
    let options = parse(arguments: arguments)
    let snapshot = AppleGameControllerSupportAuditor.currentSystemSnapshot()
    let audit = AppleGameControllerSupportAuditor.audit(
      snapshot: snapshot,
      records: AppleGameControllerSupportAuditor.bundledOJDRecords()
    )

    if options.json {
      encodeJSON(
        JSONOutput(audit: audit, appleEntries: options.allAppleEntries ? snapshot.entries : nil)
      )
      return
    }

    print("Apple GameController Catalog Audit")
    print("  Source       : \(audit.source.rawValue)")
    print(
      "  Version      : "
        + (audit.bundleVersions.isEmpty ? "unknown" : audit.bundleVersions.joined(separator: ", "))
    )
    print("  Apple pairs  : \(audit.appleExactDeviceCount) exact VID/PID entries")
    print("  OJD listed   : \(audit.catalogListedOJDRecordCount)/\(audit.ojdRecordCount) records")
    for warning in audit.warnings { print("  Warning      : \(warning)") }
    print("")
    print("OJD record comparison:")
    for record in audit.records {
      let marker = record.catalogListed ? "LISTED" : "not listed"
      print("  [\(marker)] \(hex(record.vendorID)):\(hex(record.productID)) \(record.name)")
      if !record.appleIdentifiers.isEmpty {
        print("    Apple IDs: \(record.appleIdentifiers.joined(separator: ", "))")
      }
      if !record.transportConstraints.isEmpty {
        print("    Transport: \(record.transportConstraints.joined(separator: ", "))")
      }
      if !record.versionConstraints.isEmpty {
        print(
          "    Versions : " + record.versionConstraints.map(String.init).joined(separator: ", ")
        )
      }
    }

    print("")
    print("Compatibility identity comparison:")
    for profile in audit.compatibilityProfiles {
      let marker = profile.appleBackedExactIdentity ? "APPLE EXACT" : "not exact-listed"
      let kind = profile.isHardwareSpoof ? "spoof" : "OJD-owned"
      print(
        "  [\(marker)] \(hex(profile.vendorID)):\(hex(profile.productID)) "
          + "\(profile.displayName) (\(kind))"
      )
      if !profile.appleIdentifiers.isEmpty {
        print("    Apple IDs: \(profile.appleIdentifiers.joined(separator: ", "))")
      }
    }

    if options.allAppleEntries {
      print("")
      print("All exact Apple catalog entries:")
      for entry in snapshot.entries {
        let names =
          entry.identifiers.isEmpty ? "(unnamed)" : entry.identifiers.joined(separator: ", ")
        print("  \(hex(entry.vendorID)):\(hex(entry.productID)) \(names)")
      }
    }

    print("")
    print(audit.caveat)
  }

  private struct Options {
    var json = false
    var allAppleEntries = false
  }

  private func parse(arguments: [String]) -> Options {
    var options = Options()
    for argument in arguments {
      switch argument {
      case "--json": options.json = true
      case "--all-apple": options.allAppleEntries = true
      case "--help", "-h", "help":
        printHelp()
        exit(0)
      default:
        printHelp()
        exit(1)
      }
    }
    return options
  }

  private func encodeJSON(_ output: JSONOutput) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(output)
      print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
      print("ERROR: Could not encode GameController catalog audit: \(error.localizedDescription)")
      exit(1)
    }
  }

  private func printHelp() {
    print(
      [
        "Usage: OpenJoystickDriver --headless diagnose gamecontroller-catalog "
          + "[--all-apple] [--json]",
        "",
        "Compares OJD profiles with Apple's private current-system GameController "
          + "mapping MobileAsset. Catalog presence is evidence, not a support guarantee.",
      ].joined(separator: "\n")
    )
  }

  private func hex(_ value: UInt16) -> String { String(format: "%04x", value) }
}
