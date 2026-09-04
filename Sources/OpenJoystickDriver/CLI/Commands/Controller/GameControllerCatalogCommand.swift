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

    CLIOutput.diagnostic(
      CLILocalized.text("cli.controller.catalogAudit", "Apple GameController Catalog Audit")
    )
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.controller.catalogSource",
        "  Source       : %@",
        audit.source.rawValue
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.controller.catalogVersion",
        "  Version      : %@",
        audit.bundleVersions.isEmpty ? "unknown" : audit.bundleVersions.joined(separator: ", ")
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.controller.applePairs",
        "  Apple pairs  : %d exact VID/PID entries",
        audit.appleExactDeviceCount
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.controller.ojdListed",
        "  OJD listed   : %d/%d records",
        audit.catalogListedOJDRecordCount,
        audit.ojdRecordCount
      )
    )
    for warning in audit.warnings {
      CLIOutput.diagnostic(
        CLILocalized.format("cli.controller.catalogWarning", "  Warning      : %@", warning)
      )
    }
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic(
      CLILocalized.text("cli.controller.recordComparison", "OJD record comparison:")
    )
    for record in audit.records {
      let marker =
        record.catalogListed
        ? CLILocalized.text("cli.controller.catalogListedMarker", "LISTED")
        : CLILocalized.text("cli.controller.catalogNotListedMarker", "not listed")
      CLIOutput.diagnostic(
        "  [\(marker)] \(hex(record.vendorID)):\(hex(record.productID)) \(record.name)"
      )
      if !record.appleIdentifiers.isEmpty {
        CLIOutput.diagnostic(
          CLILocalized.format(
            "cli.controller.appleIDs",
            "    Apple IDs: %@",
            record.appleIdentifiers.joined(separator: ", ")
          )
        )
      }
      if !record.transportConstraints.isEmpty {
        CLIOutput.diagnostic(
          CLILocalized.format(
            "cli.controller.transport",
            "    Transport: %@",
            record.transportConstraints.joined(separator: ", ")
          )
        )
      }
      if !record.versionConstraints.isEmpty {
        CLIOutput.diagnostic(
          CLILocalized.format(
            "cli.controller.catalogVersions",
            "    Versions : %@",
            record.versionConstraints.map(String.init).joined(separator: ", ")
          )
        )
      }
    }

    if options.allAppleEntries {
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic(
        CLILocalized.text("cli.controller.allAppleEntries", "All exact Apple catalog entries:")
      )
      for entry in snapshot.entries {
        let names =
          entry.identifiers.isEmpty
          ? CLILocalized.text("cli.controller.catalogUnnamed", "(unnamed)")
          : entry.identifiers.joined(separator: ", ")
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
        CLILocalized.format(
          "cli.controller.catalogEncodeFailed",
          "Could not encode GameController catalog audit: %@",
          error.localizedDescription
        )
      )
      exit(1)
    }
  }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.controller.catalogHelp",
        """
        Usage: OpenJoystickDriver --headless diagnose catalog [--all-apple] [--json]

        Compares OJD profiles with Apple's private current-system GameController \
        mapping MobileAsset. Catalog presence is evidence, not a support guarantee.
        """
      )
    )
  }

  private func hex(_ value: UInt16) -> String { String(format: "%04x", value) }
}
