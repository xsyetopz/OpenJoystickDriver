import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct AccessCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "access",
    abstract: CLILocalized.text(
      "cli.access.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.discussion"
    ),
    subcommands: [
      AccessStatusCommand.self, AccessEnableCommand.self, AccessDisableCommand.self,
      AccessListCommand.self, AccessGrantCommand.self, AccessRevokeCommand.self,
      AccessWebCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
            socketPath
          )
          : CLILocalized.text(
            "cli.access.disable.success"
          )
      )
    }
  }
}

struct AccessStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.access.status.abstract"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.accessStatus() }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(status)
      case .plain:
        CLIOutput.plain(
          [
            ["enabled", String(status.enabled)], ["socket", status.socketPath],
            [
              "web", String(status.web.enabled), String(status.web.listening),
              status.web.url ?? "",
            ],
          ]
            + status.connections.map {
              [
                "connection", $0.id, $0.identifier, AccessText.scopes($0.scopes),
                $0.transport.rawValue,
              ]
            }
        )
      case .human:
        CLIOutput.stdout(
          status.enabled
            ? CLILocalized.text("cli.access.status.on")
            : CLILocalized.text("cli.access.status.off")
        )
        CLIOutput.stdout(
          CLILocalized.format("cli.access.status.socket", status.socketPath)
        )
        CLIOutput.stdout(AccessText.web(status.web))
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.access.status.counts",
            String(status.connections.count),
            String(status.grants.count),
            String(status.refused.count)
          )
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.access.status.token_counts",
            String(status.tokens.count),
            String(status.refusedTokens.count)
          )
        )
        for connection in status.connections {
          CLIOutput.stdout(
            "  "
              + [
                connection.id, connection.identifier, AccessText.scopes(connection.scopes),
                connection.transport.rawValue,
              ].joined(separator: "  ")
          )
        }
      }
    }
  }
}

struct AccessEnableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.enable.abstract"),
    discussion: CLILocalized.text(
      "cli.access.enable.discussion"
    )
  )

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.enable.confirm"
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
      "cli.access.disable.abstract"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
      "cli.access.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.list.discussion"
    )
  )

  struct Result: Encodable, Equatable {
    let grants: [AccessGrantSummary]
    let refused: [AccessRefusedClient]
    let tokens: [AccessTokenSummary]
    let refusedTokens: [AccessRefusedToken]
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.accessStatus() }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            grants: status.grants,
            refused: status.refused,
            tokens: status.tokens,
            refusedTokens: status.refusedTokens
          )
        )
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
            + status.tokens.map {
              ["token", $0.id, $0.origins.joined(separator: ","), AccessText.scopes($0.scopes)]
            }
            + status.refusedTokens.map {
              [
                "refused-token", $0.name.map { "token:\($0)" } ?? "", $0.origin ?? "",
                AccessText.scopes($0.scopes), $0.transport.rawValue,
              ]
            }
        )
      case .human:
        CLIOutput.stdout(CLILocalized.text("cli.access.list.granted"))
        if status.grants.isEmpty {
          CLIOutput.stdout(CLILocalized.text("cli.access.list.none"))
        }
        for grant in status.grants {
          CLIOutput.stdout(
            "  \(grant.id)  \(AccessText.signer(grant.kind, grant.teamIdentifier))  "
              + "\(grant.identifier)  \(AccessText.scopes(grant.scopes))  \(grant.path)"
          )
        }
        CLIOutput.stdout(
          CLILocalized.text("cli.access.list.refused")
        )
        if status.refused.isEmpty {
          CLIOutput.stdout(CLILocalized.text("cli.access.list.none"))
        }
        for client in status.refused {
          CLIOutput.stdout(
            "  \(client.id)  \(AccessText.signer(client.kind, client.teamIdentifier))  "
              + "\(client.identifier)  \(AccessText.scopes(client.scopes))  \(client.path ?? "")"
          )
        }
        printTokens(status)
      }
    }
  }

  private func printTokens(_ status: AccessStatusPayload) {
    CLIOutput.stdout(CLILocalized.text("cli.access.list.tokens"))
    if status.tokens.isEmpty {
      CLIOutput.stdout(CLILocalized.text("cli.access.list.none"))
    }
    for token in status.tokens {
      CLIOutput.stdout(
        "  \(token.id)  \(AccessText.scopes(token.scopes))  \(token.origins.joined(separator: " "))"
      )
    }
    CLIOutput.stdout(
      CLILocalized.text("cli.access.list.refused_tokens")
    )
    if status.refusedTokens.isEmpty {
      CLIOutput.stdout(CLILocalized.text("cli.access.list.none"))
    }
    for token in status.refusedTokens {
      let name =
        token.name.map { "token:\($0)" }
        ?? CLILocalized.text("cli.access.list.unknown_token")
      CLIOutput.stdout(
        "  \(name)  \(AccessText.scopes(token.scopes))  \(token.transport.rawValue)  "
          + (token.origin ?? "")
      )
    }
  }
}

/// Text that several `ojd access` commands print.
enum AccessText {
  static var needsForce: String {
    CLILocalized.text(
      "cli.access.needs_force"
    )
  }

  /// `WebSocket: on at ws://…, pages at http://…`, or off.
  static func web(_ web: AccessWebStatus) -> String {
    guard web.enabled else {
      return CLILocalized.text("cli.access.status.web_off")
    }
    guard web.listening else {
      return CLILocalized.format(
        "cli.access.status.web_closed",
        web.port.map(String.init) ?? ""
      )
    }
    return CLILocalized.format(
      "cli.access.status.web_on",
      web.url ?? "",
      web.pagesURL ?? "",
      web.pagesPath
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
