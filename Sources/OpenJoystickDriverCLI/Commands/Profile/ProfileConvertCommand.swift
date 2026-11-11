import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// One part of a profile that `ojd profile convert` left out, in `--json` output.
struct ProfileLeftOut: Encodable, Equatable {
  /// The kind of part, such as `Binding`.
  let section: String
  /// The sources of the part that the target controller lacks, in their `SOURCE` form.
  let sources: [String]

  init(_ leftOut: RemappingProfileConversion.LeftOut) {
    section = leftOut.section.rawValue
    sources = leftOut.sources.map(ProfileText.source)
  }

  /// The human line that names the part and why it was left out.
  var line: String {
    let kind = CommandLineName.kebab(section)
    return sources.isEmpty
      ? CLILocalized.format("cli.profile.convert.leftOutPart", kind)
      : CLILocalized.format("cli.profile.convert.leftOut", kind, sources.joined(separator: ", "))
  }
}

/// The `ojd profile convert` command: copies a profile for another controller model, keeping the
/// parts the model can use and listing the rest.
struct ProfileConvertCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "convert",
    abstract: CLILocalized.text("cli.profile.convert.abstract")
  )

  /// The profile to convert.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// `--controller`: the target model as `VVVV:PPPP`, or the ID of a connected controller.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.convert.controller"),
      valueName: "controller"
    )
  )
  var controller: ControllerSelector

  /// `--name`: the name of the converted profile.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.convert.name"),
      valueName: "name"
    )
  )
  var name: String?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, target, newName) = (profile, controller, name)
      let (conversion, snapshot) = try await ServiceConnection.request { client in
        let (original, _) = try await selector.resolve(with: client)
        let device: RemappingDeviceScope
        switch target.reference {
        case .model(let model):
          device = RemappingDeviceScope(vendorID: model.vendorID, productID: model.productID)
        case .session, .port:
          let found = try await target.resolve(with: client)
          device = RemappingDeviceScope(vendorID: found.vendorID, productID: found.productID)
        }
        let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
        let identity = deviceIdentity(
          vendorID: Int(device.vendorID),
          productID: Int(device.productID)
        )
        let converted = RemappingProfileConversion(
          converting: original,
          to: device,
          name: newName ?? "\(original.name) \(identity)",
          capabilities: ProtocolDriverRegistry().profileCapabilities(for: model) ?? .unknown
        )
        let created = try await client.createRemappingProfile(
          try converted.profile.validatedForCLI()
        )
        return (converted, created)
      }
      let created = conversion.profile
      let leftOut = conversion.leftOut.map(ProfileLeftOut.init)
      let identity = deviceIdentity(
        vendorID: Int(created.device.vendorID),
        productID: Int(created.device.productID)
      )
      let message =
        ([
          CLILocalized.format(
            "cli.profile.convert.done",
            created.name,
            created.id.uuidString,
            identity
          )
        ] + leftOut.map(\.line)).joined(separator: "\n")
      try printProfile(
        ProfileResult(
          profile: try savedSummary(created.id, in: snapshot),
          changed: true,
          leftOut: leftOut
        ),
        message: message
      )
    }
  }
}
