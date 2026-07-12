import Foundation
import OpenJoystickDriverKit

struct RuntimeHealthCommand {
  func run(arguments: [String]) {
    let options = parse(arguments: arguments)
    let health = DaemonManager.health()
    guard let processID = health.pid else {
      print("ERROR: OpenJoystickDriver daemon is not running.")
      exit(1)
    }

    let policy = RuntimeHealthPolicy(
      maximumResidentBytes:
        options.residentLimitMiB == 0
        ? nil
        : UInt64(options.residentLimitMiB) * 1_048_576,
      maximumPhysicalFootprintBytes:
        options.physicalFootprintLimitMiB == 0
        ? nil
        : UInt64(options.physicalFootprintLimitMiB) * 1_048_576
    )
    let result: SamplingResult = runSyncResult {
      do {
        return .success(
          try await DaemonRuntimeHealthSampler.sample(
            processID: Int32(processID),
            seconds: options.seconds,
            intervalMilliseconds: options.intervalMilliseconds,
            policy: policy
          )
        )
      } catch {
        return .failure(error.localizedDescription)
      }
    }
    let summary: RuntimeHealthSummary
    switch result {
    case .success(let value):
      summary = value
    case .failure(let message):
      print("ERROR: \(message)")
      exit(1)
    }

    if options.json {
      encodeJSON(summary)
      return
    }
    printSummary(summary)
  }

  private enum SamplingResult: Sendable {
    case success(RuntimeHealthSummary)
    case failure(String)
  }

  private struct Options {
    var seconds = 60
    var intervalMilliseconds = 1_000
    var residentLimitMiB = 0
    var physicalFootprintLimitMiB = 512
    var json = false
  }

  private func parse(arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--seconds":
        options.seconds = parseValue(
          arguments,
          at: index,
          allowed: 1...86_400
        )
        index += 2
      case "--interval-ms":
        options.intervalMilliseconds = parseValue(
          arguments,
          at: index,
          allowed: 100...60_000
        )
        index += 2
      case "--rss-limit-mib":
        options.residentLimitMiB = parseValue(
          arguments,
          at: index,
          allowed: 0...65_536
        )
        index += 2
      case "--footprint-limit-mib":
        options.physicalFootprintLimitMiB = parseValue(
          arguments,
          at: index,
          allowed: 0...65_536
        )
        index += 2
      case "--json":
        options.json = true
        index += 1
      case "--help", "-h", "help":
        printHelp()
        exit(0)
      default:
        failUsage()
      }
    }

    let estimatedSamples =
      Int(
        ceil(
          Double(options.seconds * 1_000)
            / Double(options.intervalMilliseconds)
        )
      ) + 1
    guard estimatedSamples <= DaemonRuntimeHealthSampler.maximumSampleCount else {
      print(
        "ERROR: Configuration would collect \(estimatedSamples) samples; "
          + "increase --interval-ms."
      )
      exit(1)
    }
    return options
  }

  private func parseValue(
    _ arguments: [String],
    at index: Int,
    allowed: ClosedRange<Int>
  ) -> Int {
    guard index + 1 < arguments.count,
      let value = Int(arguments[index + 1]),
      allowed.contains(value)
    else {
      failUsage()
    }
    return value
  }

  private func encodeJSON(_ summary: RuntimeHealthSummary) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(summary)
      print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
      print("ERROR: Could not encode runtime summary: \(error.localizedDescription)")
      exit(1)
    }
  }

  private func printSummary(_ summary: RuntimeHealthSummary) {
    print("OpenJoystickDriver Daemon Runtime Soak")
    print("  Samples    : \(summary.sampleCount) over \(format(summary.durationSeconds))s")
    print(
      "  RSS        : \(mebibytes(summary.firstResidentBytes)) -> "
        + "\(mebibytes(summary.lastResidentBytes)) MiB "
        + "(peak \(mebibytes(summary.peakResidentBytes)))"
    )
    print(
      "  Footprint  : \(mebibytes(summary.firstPhysicalFootprintBytes)) -> "
        + "\(mebibytes(summary.lastPhysicalFootprintBytes)) MiB "
        + "(peak \(mebibytes(summary.peakPhysicalFootprintBytes)))"
    )
    print(
      "  RSS rate   : \(signedMebibytes(summary.residentGrowthBytesPerHour)) MiB/hour"
    )
    print(
      "  Foot rate  : "
        + "\(signedMebibytes(summary.physicalFootprintGrowthBytesPerHour)) MiB/hour"
    )
    print(
      "  FDs        : \(summary.firstFileDescriptorCount) -> "
        + "\(summary.lastFileDescriptorCount) "
        + "(peak \(summary.peakFileDescriptorCount))"
    )
    print(
      "  Threads    : \(summary.firstThreadCount) -> "
        + "\(summary.lastThreadCount) (peak \(summary.peakThreadCount))"
    )
    print("  CPU avg    : \(format(summary.averageCPUPercent))%")
    print("  RSS trend  : \(summary.memoryTrend.rawValue)")
    print("  Foot trend : \(summary.physicalMemoryTrend.rawValue)")
    if let limit = summary.residentLimitBytes {
      print("  RSS limit  : \(mebibytes(limit)) MiB")
    }
    if let limit = summary.physicalFootprintLimitBytes {
      print("  Foot limit : \(mebibytes(limit)) MiB")
    }
    print("  Verdict    : \(summary.soakVerdict.rawValue)")
    if summary.soakVerdict == .insufficientData {
      print(
        "Observation shorter than \(summary.minimumSoakSeconds)s is inconclusive; "
          + "use a longer active-controller soak."
      )
    } else {
      print(
        "A stable bounded soak is evidence for this workload, not proof that all leaks are absent."
      )
    }
  }

  private func failUsage() -> Never {
    printHelp()
    exit(1)
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless diagnose runtime
      [--seconds 1...86400] [--interval-ms 100...60000]
      [--rss-limit-mib 0...65536] [--footprint-limit-mib 0...65536] [--json]

      Samples daemon RSS, physical footprint, CPU, file descriptors, and threads.
      Zero disables a high-water limit; footprint defaults to 512 MiB. Windows under 60 seconds
      are explicitly inconclusive; use a longer soak while reproducing activity.
      At most 100000 samples may be requested.
      """
    )
  }

  private func mebibytes(_ bytes: UInt64) -> String {
    format(Double(bytes) / 1_048_576)
  }

  private func signedMebibytes(_ bytesPerHour: Double) -> String {
    let value = bytesPerHour / 1_048_576
    return value >= 0 ? "+\(format(value))" : format(value)
  }

  private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}
