import Foundation

extension RemappingProfile {
  /// Checks that an axis tuning is finite and within its ranges.
  /// - Throws: ``RemappingValidationError/nonFiniteTuning(index:field:)`` or
  ///   ``RemappingValidationError/tuningOutOfRange(index:field:)``.
  internal static func validate(_ tuning: RemappingAxisTuning, at index: Int) throws {
    let fields = [
      ("deadzone", tuning.deadzone, RemappingAxisTuning.deadzoneRange),
      ("gain", tuning.gain, RemappingAxisTuning.gainRange),
      (
        "digital activation threshold", tuning.digitalActivationThreshold,
        RemappingAxisTuning.digitalActivationThresholdRange
      ),
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

  /// Checks that a turbo setting is finite and within its ranges.
  /// - Throws: ``RemappingValidationError/nonFiniteTurbo(index:field:)`` or
  ///   ``RemappingValidationError/turboOutOfRange(index:field:)``.
  internal static func validate(_ turbo: RemappingTurbo, at index: Int) throws {
    let fields = [
      ("repeat rate", turbo.repeatRateHz, RemappingTurbo.repeatRateHzRange),
      ("duty cycle", turbo.dutyCycle, RemappingTurbo.dutyCycleRange),
      ("initial delay", turbo.initialDelayMs, RemappingTurbo.initialDelayMsRange),
    ]
    for (field, value, range) in fields {
      guard value.isFinite else {
        throw RemappingValidationError.nonFiniteTurbo(index: index, field: field)
      }
      guard range.contains(value) else {
        throw RemappingValidationError.turboOutOfRange(index: index, field: field)
      }
    }
    if let cap = turbo.maxRepeats, !RemappingTurbo.maxRepeatsRange.contains(cap) {
      throw RemappingValidationError.turboOutOfRange(index: index, field: "max repeats")
    }
  }

  /// Checks that a long-hold duration is finite and within its range.
  /// - Throws: ``RemappingValidationError/nonFiniteLongHold(index:field:)`` or
  ///   ``RemappingValidationError/longHoldOutOfRange(index:field:)``.
  internal static func validate(_ longHold: RemappingLongHold, at index: Int) throws {
    guard longHold.durationMs.isFinite else {
      throw RemappingValidationError.nonFiniteLongHold(index: index, field: "duration")
    }
    guard RemappingLongHold.durationRange.contains(longHold.durationMs) else {
      throw RemappingValidationError.longHoldOutOfRange(index: index, field: "duration")
    }
  }

  /// Checks that tap counts are unique and that each entry has a count and a finite window in
  /// range.
  /// - Throws: ``RemappingValidationError/nonFiniteMultiTap(index:field:)``,
  ///   ``RemappingValidationError/multiTapOutOfRange(index:field:)`` or
  ///   ``RemappingValidationError/duplicateMultiTapCount(index:)``.
  internal static func validate(_ multiTap: [RemappingMultiTap], at index: Int) throws {
    for tap in multiTap {
      guard tap.windowMs.isFinite else {
        throw RemappingValidationError.nonFiniteMultiTap(index: index, field: "window")
      }
      guard RemappingMultiTap.countRange.contains(tap.count) else {
        throw RemappingValidationError.multiTapOutOfRange(index: index, field: "count")
      }
      guard RemappingMultiTap.windowRange.contains(tap.windowMs) else {
        throw RemappingValidationError.multiTapOutOfRange(index: index, field: "window")
      }
    }
    guard Set(multiTap.map(\.count)).count == multiTap.count else {
      throw RemappingValidationError.duplicateMultiTapCount(index: index)
    }
  }

  /// Whether a string is a bundle identifier: ASCII, within the length range, at least two
  /// dot-separated parts, each starting and ending with a letter or digit and holding only letters,
  /// digits and hyphens.
  internal static func isValidAppID(_ identifier: String) -> Bool {
    guard Self.appIDLengthRange.contains(identifier.utf8.count),
      identifier.allSatisfy({ $0.isASCII })
    else { return false }
    let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2 else { return false }
    return components.allSatisfy { component in
      guard let first = component.first, let last = component.last,
        first.isLetter || first.isNumber, last.isLetter || last.isNumber
      else { return false }
      return component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }
}
