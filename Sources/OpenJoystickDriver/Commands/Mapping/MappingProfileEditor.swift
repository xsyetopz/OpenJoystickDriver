import Foundation
import OpenJoystickDriverKit

enum MappingProfileEditor {
  static func replacingBinding(
    in profile: RemappingProfile,
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let axisTuning = try tuning(source: source, options: options)
    let turbo = try turbo(destination: destination, options: options)
    let existingID = profile.bindings.first { $0.source == source }?.id
    let replacement = RemappingBinding(
      id: existingID ?? UUID(),
      source: source,
      destination: destination,
      axisTuning: axisTuning,
      turbo: turbo
    )
    let bindings = profile.bindings.filter { $0.source != source } + [replacement]
    let updated = copy(profile, bindings: bindings)
    try updated.validate()
    return updated
  }

  static func removingBinding(from profile: RemappingProfile, source: RemappingSource) throws
    -> RemappingProfile
  {
    guard profile.bindings.contains(where: { $0.source == source }) else {
      throw MappingCommandError.invalidArguments("No binding exists for the requested source.")
    }
    return copy(profile, bindings: profile.bindings.filter { $0.source != source })
  }

  static func updating(_ profile: RemappingProfile, options: MappingOptions) throws
    -> RemappingProfile
  {
    let vendorID =
      try options["--vid"].map { try MappingSyntax.identifier($0, option: "--vid") }
      ?? profile.device.vendorID
    let productID =
      try options["--pid"].map { try MappingSyntax.identifier($0, option: "--pid") }
      ?? profile.device.productID
    let scope = try applicationScope(options, defaultValue: profile.applicationScope)
    let updated = RemappingProfile(
      id: profile.id,
      name: options["--name"] ?? profile.name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: scope,
      bindings: profile.bindings
    )
    try updated.validate()
    return updated
  }

  static func applicationScope(
    _ options: MappingOptions,
    defaultValue: RemappingApplicationScope? = nil
  ) throws -> RemappingApplicationScope {
    let bundleID = options["--target-app"]
    let global = options.contains("--global")
    guard bundleID == nil || !global else {
      throw MappingCommandError.invalidArguments("Pass only one of --target-app or --global.")
    }
    if let bundleID { return .application(bundleIdentifier: bundleID) }
    if global { return .global }
    guard let defaultValue else {
      throw MappingCommandError.invalidArguments("Pass one of --target-app or --global.")
    }
    return defaultValue
  }

  private static func tuning(source: RemappingSource, options: MappingOptions) throws
    -> RemappingAxisTuning?
  {
    let tuningOptions = [
      "--deadzone", "--gain", "--invert", "--response-curve",
      "--digital-threshold",
    ]
    let supplied = tuningOptions.contains(where: options.contains)
    let isAxis =
      switch source {
      case .axis, .axisDirection: true
      default: false
      }
    guard isAxis || !supplied else {
      throw MappingCommandError.invalidArguments("Axis options require an axis source.")
    }
    guard isAxis else { return nil }
    return RemappingAxisTuning(
      deadzone: try number(options["--deadzone"], option: "--deadzone", fallback: 0.1),
      gain: try number(options["--gain"], option: "--gain", fallback: 1),
      inverted: options.contains("--invert"),
      responseCurve: try curve(options["--response-curve"]),
      digitalActivationThreshold: try number(
        options["--digital-threshold"],
        option: "--digital-threshold",
        fallback: 0.5
      )
    )
  }

  private static func turbo(destination: RemappingDestination, options: MappingOptions) throws
    -> RemappingTurbo?
  {
    let rate = options["--turbo-rate"]
    let duty = options["--turbo-duty"]
    guard rate != nil || duty != nil else { return nil }
    guard let rate, let duty else {
      throw MappingCommandError.invalidArguments(
        "--turbo-rate and --turbo-duty must be supplied together."
      )
    }
    guard destination.acceptsTurbo else {
      throw MappingCommandError.invalidArguments(
        "Turbo is not supported for pointer movement or scrolling."
      )
    }
    return RemappingTurbo(
      repeatRateHz: try MappingSyntax.finiteDouble(rate, option: "--turbo-rate"),
      dutyCycle: try MappingSyntax.finiteDouble(duty, option: "--turbo-duty")
    )
  }

  private static func number(_ raw: String?, option: String, fallback: Double) throws -> Double {
    guard let raw else { return fallback }
    return try MappingSyntax.finiteDouble(raw, option: option)
  }

  private static func curve(_ raw: String?) throws -> RemappingResponseCurve {
    guard let raw else { return .linear }
    guard let value = RemappingResponseCurve(rawValue: raw) else {
      throw MappingCommandError.invalidArguments("Unknown response curve '\(raw)'.")
    }
    return value
  }

  private static func copy(_ profile: RemappingProfile, bindings: [RemappingBinding])
    -> RemappingProfile
  {
    RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings
    )
  }
}
