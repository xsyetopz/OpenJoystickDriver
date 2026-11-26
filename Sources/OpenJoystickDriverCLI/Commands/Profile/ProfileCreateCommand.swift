import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile create` command: creates an empty, inactive profile for one controller model.
struct ProfileCreateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "create",
    abstract: CLILocalized.text(
      "cli.profile.create.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.create.discussion"
    ) + "\n\n" + CLILocalized.text("cli.profile.create.examples")
  )

  /// The name of the profile.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.group.name"),
      valueName: "name"
    )
  )
  var name: String

  /// `--controller`: the controller model as `VVVV:PPPP`, or the ID of a connected controller.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.controller"
      ),
      valueName: "controller"
    )
  )
  var controller: ControllerSelector

  /// `--app`: the bundle ID of an app that the profile applies to, repeated for more apps;
  /// without it the profile applies in every app.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.app"
      ),
      valueName: "app-id"
    )
  )
  var app: [String] = []

  /// `--virtual-gamepad`: `disabled` publishes no virtual gamepad, `mapped` sends only the bound
  /// controls, and `passthrough` also sends the unbound controls.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.create.virtualGamepad"
      )
    )
  )
  var virtualGamepad: RemappingVirtualGamepadPolicy = .passthrough

  /// `--physical-input`: `shared` lets the profile send input while the native physical input stays
  /// visible, and `exclusive` requires confirmed exclusive ownership of the controller.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "platform.macos.cli.profile.create.physicalInput"
      )
    )
  )
  var physicalInput: RemappingPhysicalInputPolicy = .shared

  /// `--template`: starts the profile from a template instead of empty.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.template"),
      valueName: "template"
    )
  )
  var template: ProfileTemplate?

  /// `--stick`: the stick that the `gyro-stick` template drives.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.stick"),
      valueName: "stick"
    )
  )
  var stick: RemappingGyroStickTemplate.Stick?

  /// `--activation`: the control that must be held for gyro output; without it gyro output is
  /// always on.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.create.activation"),
      valueName: "control"
    )
  )
  var activation: String?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard template == .gyroStick || (stick == nil && activation == nil) else {
        throw CLIFailure.usage(CLILocalized.text("cli.profile.create.templateRequired"))
      }
      let activationSource = try activation.map(parseSource)
      let selector = controller
      let scope = app.isEmpty ? RemappingApplicationScope.global : .application(appIDs: app)
      let policy = RemappingOutputPolicy(
        virtualGamepad: virtualGamepad,
        physicalInput: physicalInput
      )
      let profileName = name
      let (created, skippedControls, snapshot) = try await ServiceConnection.request { client in
        let device: RemappingDeviceScope
        switch selector.reference {
        case .model(let model):
          device = RemappingDeviceScope(vendorID: model.vendorID, productID: model.productID)
        case .session, .port:
          let found = try await selector.resolve(with: client)
          device = RemappingDeviceScope(vendorID: found.vendorID, productID: found.productID)
        }
        let profile: RemappingProfile
        var skipped: [Control]?
        let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
        let capabilities = ProtocolDriverRegistry().profileCapabilities(for: model) ?? .unknown
        func fromBindings(_ bindings: RemappingBindingTemplate) throws -> RemappingProfile {
          let made = bindings.profile(
            name: profileName,
            device: device,
            applicationScope: scope,
            outputPolicy: policy,
            capabilities: capabilities
          )
          skipped = made.skipped
          return try made.profile.validatedForCLI()
        }
        switch template {
        case .keyboardNavigation: profile = try fromBindings(.keyboardNavigation)
        case .mouseClicks: profile = try fromBindings(.mouseClicks)
        case .gyroStick:
          do {
            profile = try RemappingGyroStickTemplate.profile(
              name: profileName,
              device: device,
              applicationScope: scope,
              stick: stick ?? .right,
              activation: activationSource,
              capabilities: capabilities
            ).validatedForCLI()
          } catch RemappingGyroStickTemplate.Failure.noMotionSensor(let model) {
            throw CLIFailure(
              .invalidProfile,
              CLILocalized.format("cli.profile.create.noMotion", model.description)
            )
          }
        case nil:
          profile = try RemappingProfile(
            name: profileName,
            device: device,
            applicationScope: scope,
            outputPolicy: policy,
            bindings: []
          ).validatedForCLI()
        }
        return (profile, skipped, try await client.createRemappingProfile(profile))
      }
      var message = CLILocalized.format(
        "cli.profile.create.done",
        created.name,
        created.id.uuidString
      )
      if let skippedControls, !skippedControls.isEmpty {
        message +=
          "\n"
          + CLILocalized.format(
            "cli.profile.create.skipped",
            skippedControls.map(\.rawValue).joined(separator: ", ")
          )
      }
      try printProfile(
        ProfileResult(
          profile: try savedSummary(created.id, in: snapshot),
          changed: true,
          skippedControls: skippedControls
        ),
        message: message
      )
    }
  }
}
