import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct AccessCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "access",
    abstract: CLILocalized.text(
      "cli.access.abstract",
      "Turn on the endpoint and choose which programs may read controllers through it."
    ),
    discussion: CLILocalized.text(
      "cli.access.discussion",
      "The endpoint is a local socket that granted programs read controller events from. It is "
        + "off until you run 'ojd access enable', and the service serves only programs whose "
        + "signature you granted."
    ),
    subcommands: [
      AccessStatusCommand.self, AccessEnableCommand.self, AccessDisableCommand.self,
      AccessListCommand.self, AccessGrantCommand.self, AccessRevokeCommand.self,
    ]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// The `--json` result of `access enable` and `access disable`.
struct AccessEnabledResult: Encodable, Equatable {
  let enabled: Bool
  let socketPath: String

  func print() throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(self)
    case .plain: CLIOutput.plain([[String(enabled), socketPath]])
    case .human:
      CLIOutput.success(
        enabled
          ? CLILocalized.format(
            "cli.access.enable.success",
            "The endpoint listens on %@.",
            socketPath
          )
          : CLILocalized.text(
            "cli.access.disable.success",
            "The endpoint is off, and its connections are closed."
          )
      )
    }
  }
}

struct AccessStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.access.status.abstract",
      "Show whether the endpoint is on, its socket, and its connected clients."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.accessStatus() }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(status)
      case .plain:
        CLIOutput.plain(
          [["enabled", String(status.enabled)], ["socket", status.socketPath]]
            + status.connections.map {
              ["connection", $0.id, $0.identifier, AccessText.scopes($0.scopes)]
            }
        )
      case .human:
        CLIOutput.stdout(
          status.enabled
            ? CLILocalized.text("cli.access.status.on", "Endpoint: on")
            : CLILocalized.text("cli.access.status.off", "Endpoint: off")
        )
        CLIOutput.stdout(
          CLILocalized.format("cli.access.status.socket", "Socket: %@", status.socketPath)
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.access.status.counts",
            "Connected clients: %@. Granted clients: %@. Refused in the last 24 hours: %@.",
            String(status.connections.count),
            String(status.grants.count),
            String(status.refused.count)
          )
        )
        for connection in status.connections {
          CLIOutput.stdout(
            "  \(connection.id)  \(connection.identifier)  \(AccessText.scopes(connection.scopes))"
          )
        }
      }
    }
  }
}

struct AccessEnableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.enable.abstract", "Turn on the endpoint."),
    discussion: CLILocalized.text(
      "cli.access.enable.discussion",
      "Asks for confirmation first. Only granted programs can use the endpoint; add them with "
        + "'ojd access grant'."
    )
  )

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.enable.confirm",
          "Turn on the endpoint, so that the programs you grant can read every controller's input?"
        ),
        force: force,
        needsForce: AccessText.needsForce
      )
      let status = try await ServiceConnection.request { try await $0.setAccessEnabled(true) }
      try AccessEnabledResult(enabled: status.enabled, socketPath: status.socketPath).print()
    }
  }
}

struct AccessDisableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: CLILocalized.text(
      "cli.access.disable.abstract",
      "Turn off the endpoint and close its connections; grants are kept."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.setAccessEnabled(false) }
      try AccessEnabledResult(enabled: status.enabled, socketPath: status.socketPath).print()
    }
  }
}

struct AccessListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.access.list.abstract",
      "List granted clients and the clients refused in the last 24 hours."
    ),
    discussion: CLILocalized.text(
      "cli.access.list.discussion",
      "Each client has an ID that 'ojd access grant' and 'ojd access revoke' accept."
    )
  )

  struct Result: Encodable, Equatable {
    let grants: [AccessGrantSummary]
    let refused: [AccessRefusedClient]
  }

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.accessStatus() }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(grants: status.grants, refused: status.refused))
      case .plain:
        CLIOutput.plain(
          status.grants.map {
            [
              "granted", $0.id, $0.kind.rawValue, $0.identifier, $0.teamIdentifier ?? "",
              AccessText.scopes($0.scopes),
            ]
          }
            + status.refused.map {
              [
                "refused", $0.id, $0.kind.rawValue, $0.identifier, $0.teamIdentifier ?? "",
                AccessText.scopes($0.scopes),
              ]
            }
        )
      case .human:
        CLIOutput.stdout(CLILocalized.text("cli.access.list.granted", "Granted:"))
        if status.grants.isEmpty {
          CLIOutput.stdout(CLILocalized.text("cli.access.list.none", "  None"))
        }
        for grant in status.grants {
          CLIOutput.stdout(
            "  \(grant.id)  \(AccessText.signer(grant.kind, grant.teamIdentifier))  "
              + "\(grant.identifier)  \(AccessText.scopes(grant.scopes))  \(grant.path)"
          )
        }
        CLIOutput.stdout(
          CLILocalized.text("cli.access.list.refused", "Refused in the last 24 hours:")
        )
        if status.refused.isEmpty {
          CLIOutput.stdout(CLILocalized.text("cli.access.list.none", "  None"))
        }
        for client in status.refused {
          CLIOutput.stdout(
            "  \(client.id)  \(AccessText.signer(client.kind, client.teamIdentifier))  "
              + "\(client.identifier)  \(AccessText.scopes(client.scopes))  \(client.path ?? "")"
          )
        }
      }
    }
  }
}

/// Text that several `ojd access` commands print.
enum AccessText {
  static var needsForce: String {
    CLILocalized.text(
      "cli.access.needs_force",
      "This change gives programs access to your controllers. Add --force to confirm it without "
        + "a prompt."
    )
  }

  static func scopes(_ scopes: [EndpointScope]) -> String {
    scopes.map(\.rawValue).joined(separator: ",")
  }

  /// `team ABCDE12345`, `apple`, or `ad-hoc`.
  static func signer(_ kind: CodeSigningIdentity.Kind, _ team: String?) -> String {
    [kind.rawValue, kind == .team ? team : nil].compactMap(\.self).joined(separator: " ")
  }
}
