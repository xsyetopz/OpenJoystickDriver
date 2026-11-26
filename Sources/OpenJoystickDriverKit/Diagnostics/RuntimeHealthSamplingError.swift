public import Foundation

/// The failures of a soak run.
public enum RuntimeHealthSamplingError: LocalizedError, Sendable {
  /// The process cannot be read; the value is its process ID.
  case processUnavailable(Int32)
  /// The seconds or the interval is outside its range.
  case invalidConfiguration
  /// The run would take more than ``ApplicationServiceRuntimeHealthSampler/maximumSampleCount``
  /// samples; the value is the count.
  case tooManySamples(Int)
  /// The run took no samples.
  case noSamples

  /// The description of the error for the user.
  public var errorDescription: String? {
    let localization = Localization()
    switch self {
    case .processUnavailable(let pid):
      return localization.formatted(
        "cli.diagnose.group.soakErrorProcessUnavailable",
        arguments: [pid]
      )
    case .invalidConfiguration:
      return localization.formatted(
        "cli.diagnose.group.soakErrorInvalidConfiguration",
        arguments: [
          ApplicationServiceRuntimeHealthSampler.secondsRange.lowerBound,
          ApplicationServiceRuntimeHealthSampler.secondsRange.upperBound,
          ApplicationServiceRuntimeHealthSampler.intervalMillisecondsRange.lowerBound,
          ApplicationServiceRuntimeHealthSampler.intervalMillisecondsRange.upperBound,
        ]
      )
    case .tooManySamples(let count):
      return localization.plural(
        "cli.diagnose.group.soakErrorTooManySamples",
        arguments: [count]
      )
    case .noSamples: return localization.string("cli.diagnose.group.soakErrorNoSamples")
    }
  }
}
