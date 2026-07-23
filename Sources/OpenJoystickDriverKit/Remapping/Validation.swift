import Foundation

public enum RemappingValidationError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchemaVersion(Int)
  case invalidProfileName
  case tooManyBindings(Int)
  case duplicateBindingID(UUID)
  case duplicateSource(RemappingSource)
  case invalidBundleIdentifier(String)
  case axisTuningRequired(index: Int)
  case axisTuningNotApplicable(index: Int)
  case incompatibleSourceAndDestination(index: Int)
  case nonFiniteTuning(index: Int, field: String)
  case tuningOutOfRange(index: Int, field: String)
  case turboNotSupported(index: Int)
  case nonFiniteTurbo(index: Int, field: String)
  case turboOutOfRange(index: Int, field: String)
  case encodingFailed
  case encodedSizeExceeded(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      "Unsupported remapping profile schema version: \(version)."
    case .invalidProfileName:
      "Profile names must contain 1 through 80 printable characters."
    case .tooManyBindings(let count):
      "A remapping profile cannot contain \(count) bindings."
    case .duplicateBindingID(let id):
      "The binding identifier \(id.uuidString) is duplicated."
    case .duplicateSource:
      "Each controller source can appear in only one binding."
    case .invalidBundleIdentifier(let identifier):
      "The target application bundle identifier is invalid: \(identifier)."
    case .axisTuningRequired(let index):
      "Binding \(index) requires axis tuning."
    case .axisTuningNotApplicable(let index):
      "Binding \(index) cannot have axis tuning."
    case .incompatibleSourceAndDestination(let index):
      "Binding \(index) combines incompatible source and destination types."
    case .nonFiniteTuning(let index, let field):
      "Binding \(index) has a non-finite \(field)."
    case .tuningOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range \(field)."
    case .turboNotSupported(let index):
      "Binding \(index) uses turbo with a continuous destination."
    case .nonFiniteTurbo(let index, let field):
      "Binding \(index) has a non-finite turbo \(field)."
    case .turboOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range turbo \(field)."
    case .encodingFailed:
      "The remapping profile could not be encoded."
    case .encodedSizeExceeded(let size):
      "The encoded remapping profile is too large (\(size) bytes)."
    }
  }
}

extension RemappingProfile {
  /// Validates the complete persistence and dispatch contract for this profile.
  public func validate() throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw RemappingValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    try validateName()
    try validateApplicationScope()
    guard bindings.count <= Self.maximumBindingCount else {
      throw RemappingValidationError.tooManyBindings(bindings.count)
    }

    var bindingIDs: Set<UUID> = []
    var sources: Set<RemappingSource> = []
    for (index, binding) in bindings.enumerated() {
      guard bindingIDs.insert(binding.id).inserted else {
        throw RemappingValidationError.duplicateBindingID(binding.id)
      }
      guard sources.insert(binding.source).inserted else {
        throw RemappingValidationError.duplicateSource(binding.source)
      }
      try validate(binding, at: index)
    }

    let encodedSize: Int
    do {
      encodedSize = try JSONEncoder().encode(self).count
    } catch {
      throw RemappingValidationError.encodingFailed
    }
    guard encodedSize <= Self.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(encodedSize)
    }
  }

  private func validateName() throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == name, (1...80).contains(name.count),
      name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
      throw RemappingValidationError.invalidProfileName
    }
  }

  private func validateApplicationScope() throws {
    guard case .application(let identifier) = applicationScope else { return }
    guard Self.isValidBundleIdentifier(identifier) else {
      throw RemappingValidationError.invalidBundleIdentifier(identifier)
    }
  }

  private func validate(_ binding: RemappingBinding, at index: Int) throws {
    let isAxisSource: Bool
    switch binding.source {
    case .axis, .axisDirection: isAxisSource = true
    case .button, .dpad: isAxisSource = false
    }

    if isAxisSource {
      guard let tuning = binding.axisTuning else {
        throw RemappingValidationError.axisTuningRequired(index: index)
      }
      try Self.validate(tuning, at: index)
    } else if binding.axisTuning != nil {
      throw RemappingValidationError.axisTuningNotApplicable(index: index)
    }

    switch binding.source {
    case .axis:
      guard binding.destination.isContinuous else {
        throw RemappingValidationError.incompatibleSourceAndDestination(index: index)
      }
    case .axisDirection, .button, .dpad:
      guard !binding.destination.isContinuous else {
        throw RemappingValidationError.incompatibleSourceAndDestination(index: index)
      }
    }

    if let turbo = binding.turbo {
      guard binding.destination.acceptsTurbo else {
        throw RemappingValidationError.turboNotSupported(index: index)
      }
      try Self.validate(turbo, at: index)
    }
  }

  private static func validate(_ tuning: RemappingAxisTuning, at index: Int) throws {
    let fields = [
      ("deadzone", tuning.deadzone, 0.0...0.95),
      ("gain", tuning.gain, 0.1...10.0),
      ("digital activation threshold", tuning.digitalActivationThreshold, 0.01...1.0),
    ]
    for (field, value, range) in fields {
      guard value.isFinite else {
        throw RemappingValidationError.nonFiniteTuning(index: index, field: field)
      }
      guard range.contains(value) else {
        throw RemappingValidationError.tuningOutOfRange(index: index, field: field)
      }
    }
  }

  private static func validate(_ turbo: RemappingTurbo, at index: Int) throws {
    let fields = [
      ("repeat rate", turbo.repeatRateHz, 1.0...60.0),
      ("duty cycle", turbo.dutyCycle, 0.05...0.95),
    ]
    for (field, value, range) in fields {
      guard value.isFinite else {
        throw RemappingValidationError.nonFiniteTurbo(index: index, field: field)
      }
      guard range.contains(value) else {
        throw RemappingValidationError.turboOutOfRange(index: index, field: field)
      }
    }
  }

  private static func isValidBundleIdentifier(_ identifier: String) -> Bool {
    guard (3...255).contains(identifier.utf8.count), identifier.allSatisfy({ $0.isASCII }) else {
      return false
    }
    let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2 else { return false }
    return components.allSatisfy { component in
      guard let first = component.first, let last = component.last,
        first.isLetter || first.isNumber,
        last.isLetter || last.isNumber
      else {
        return false
      }
      return component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }
}
