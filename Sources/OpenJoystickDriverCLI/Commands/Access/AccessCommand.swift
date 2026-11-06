import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd access` command group: turn the endpoint on or off and choose which programs and tokens
/// may use it.
struct AccessCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "access",
    abstract: CLILocalized.text(
      "cli.access.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.group.discussion"
    ),
    subcommands: [
      AccessStatusCommand.self, AccessEnableCommand.self, AccessDisableCommand.self,
      AccessListCommand.self, AccessGrantCommand.self, AccessRevokeCommand.self,
      AccessWebCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `--json` result of `access enable` and `access disable`.
struct AccessEnabledResult: Encodable, Equatable {
  /// Whether the endpoint is on.
  let enabled: Bool
  /// The path of the endpoint's local socket.
  let socketPath: String

  /// Prints the result as JSON, as one `--plain` record, or as a success message on stderr.
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

/// The `ojd access status` command: prints whether the endpoint is on, its socket, the WebSocket,
/// the connected clients and the counts of grants and tokens.
struct AccessStatusCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.access.status.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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
                CommandLineName.kebab($0.transport.rawValue),
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
            "cli.access.status.tokenCounts",
            String(status.tokens.count),
            String(status.refusedTokens.count)
          )
        )
        for connection in status.connections {
          CLIOutput.stdout(
            "  "
              + [
                connection.id, connection.identifier, AccessText.scopes(connection.scopes),
                CommandLineName.kebab(connection.transport.rawValue),
              ].joined(separator: "  ")
          )
        }
      }
    }
  }
}

/// The `ojd access enable` command: turns the endpoint on after a confirmation.
///
/// In a script it needs `--force`.
struct AccessEnableCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.enable.abstract"),
    discussion: CLILocalized.text(
      "cli.access.enable.discussion"
    )
  )

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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

/// The `ojd access disable` command: turns the endpoint off and closes its connections.
///
/// The grants stay.
struct AccessDisableCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: CLILocalized.text(
      "cli.access.disable.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request { try await $0.setAccessEnabled(false) }
      try AccessEnabledResult(enabled: status.enabled, socketPath: status.socketPath).print()
    }
  }
}

/// The `ojd access list` command: prints the granted clients and tokens, and the clients and tokens
/// that the endpoint refused.
struct AccessListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.access.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.list.discussion"
    )
  )

  /// The `--json` result of `access list`.
  struct Result: Encodable, Equatable {
    /// The clients that hold a grant.
    let grants: [AccessGrantSummary]
    /// The clients that the endpoint refused.
    let refused: [AccessRefusedClient]
    /// The tokens that hold a grant.
    let tokens: [AccessTokenSummary]
    /// The token connections that the endpoint refused.
    let refusedTokens: [AccessRefusedToken]
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
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
              "granted", $0.id, CommandLineName.kebab($0.publisher.kind.rawValue), $0.identifier,
              $0.publisher.id ?? "", AccessText.scopes($0.scopes),
            ]
          }
            + status.refused.map {
              [
                "refused", $0.id, CommandLineName.kebab($0.publisher.kind.rawValue), $0.identifier,
                $0.publisher.id ?? "", AccessText.scopes($0.scopes),
              ]
            }
            + status.tokens.map {
              ["token", $0.id, $0.origins.joined(separator: ","), AccessText.scopes($0.scopes)]
            }
            + status.refusedTokens.map {
              [
                "refused-token", $0.name.map { "token:\($0)" } ?? "", $0.origin ?? "",
                AccessText.scopes($0.scopes), CommandLineName.kebab($0.transport.rawValue),
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
            "  \(grant.id)  \(AccessText.signer(grant.publisher.kind, grant.publisher.id))  "
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
            "  \(client.id)  "
              + "\(AccessText.signer(client.publisher.kind, client.publisher.id))  "
              + "\(client.identifier)  \(AccessText.scopes(client.scopes))  \(client.path ?? "")"
          )
        }
        printTokens(status)
      }
    }
  }

  /// Prints the granted and the refused tokens in the human output of `access list`.
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
      CLILocalized.text("cli.access.list.refusedTokens")
    )
    if status.refusedTokens.isEmpty {
      CLIOutput.stdout(CLILocalized.text("cli.access.list.none"))
    }
    for token in status.refusedTokens {
      let name =
        token.name.map { "token:\($0)" }
        ?? CLILocalized.text("cli.access.list.unknownToken")
      CLIOutput.stdout(
        "  \(name)  \(AccessText.scopes(token.scopes))  "
          + "\(CommandLineName.kebab(token.transport.rawValue))  " + (token.origin ?? "")
      )
    }
  }
}

/// Text that several `ojd access` commands print.
enum AccessText {
  /// The message that says `--force` is needed to confirm without a terminal.
  static var needsForce: String {
    CLILocalized.text(
      "cli.access.group.needsForce"
    )
  }

  /// The WebSocket line of `access status`: `WebSocket: on at ws://…, pages at http://…`, or off.
  static func web(_ web: AccessWebStatus) -> String {
    guard web.enabled else {
      return CLILocalized.text("cli.access.status.webOff")
    }
    guard web.listening else {
      return CLILocalized.format(
        "cli.access.status.webClosed",
        web.port.map(String.init) ?? ""
      )
    }
    return CLILocalized.format(
      "cli.access.status.webOn",
      web.url ?? "",
      web.pagesURL ?? "",
      web.pagesPath
    )
  }

  /// The scopes as a comma-separated list of their command-line names.
  static func scopes(_ scopes: [EndpointScope]) -> String {
    scopes.map(\.commandLineName).joined(separator: ",")
  }

  /// The signer of a client: `signed ABCDE12345`, `platform`, or `ad-hoc`.
  static func signer(_ kind: CodeSigningIdentity.Kind, _ team: String?) -> String {
    [CommandLineName.kebab(kind.rawValue), kind == .signed ? team : nil].compactMap(\.self).joined(
      separator: " "
    )
  }
}
