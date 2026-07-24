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

    CLIOutput.diagnostic("Apple GameController Catalog Audit")
    CLIOutput.diagnostic("  Source       : \(audit.source.rawValue)")
    CLIOutput.diagnostic(
      "  Version      : "
        + (audit.bundleVersions.isEmpty ? "unknown" : audit.bundleVersions.joined(separator: ", "))
    )
    CLIOutput.diagnostic("  Apple pairs  : \(audit.appleExactDeviceCount) exact VID/PID entries")
    CLIOutput.diagnostic(
      "  OJD listed   : \(audit.catalogListedOJDRecordCount)/\(audit.ojdRecordCount) records"
    )
    for warning in audit.warnings { CLIOutput.diagnostic("  Warning      : \(warning)") }
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic("OJD record comparison:")
    for record in audit.records {
      let marker = record.catalogListed ? "LISTED" : "not listed"
      CLIOutput.diagnostic(
        "  [\(marker)] \(hex(record.vendorID)):\(hex(record.productID)) \(record.name)"
      )
      if !record.appleIdentifiers.isEmpty {
        CLIOutput.diagnostic("    Apple IDs: \(record.appleIdentifiers.joined(separator: ", "))")
      }
      if !record.transportConstraints.isEmpty {
        CLIOutput.diagnostic(
          "    Transport: \(record.transportConstraints.joined(separator: ", "))"
        )
      }
      if !record.versionConstraints.isEmpty {
        CLIOutput.diagnostic(
          "    Versions : " + record.versionConstraints.map(String.init).joined(separator: ", ")
        )
      }
    }

    if options.allAppleEntries {
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic("All exact Apple catalog entries:")
      for entry in snapshot.entries {
        let names =
          entry.identifiers.isEmpty ? "(unnamed)" : entry.identifiers.joined(separator: ", ")
        CLIOutput.diagnostic("  \(hex(entry.vendorID)):\(hex(entry.productID)) \(names)")
      }
    }

    CLIOutput.diagnostic("")
    CLIOutput.diagnostic(audit.caveat)
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
      CLIOutput.error(
        "Could not encode GameController catalog audit: \(error.localizedDescription)"
      )
      exit(1)
    }
  }

  private func printHelp() {
    print(
      [
        "Usage: OpenJoystickDriver --headless diagnose catalog "
          + "[--all-apple] [--json]",
        "",
        "Compares OJD profiles with Apple's private current-system GameController "
          + "mapping MobileAsset. Catalog presence is evidence, not a support guarantee.",
      ].joined(separator: "\n")
    )
  }

  private func hex(_ value: UInt16) -> String { String(format: "%04x", value) }
}
