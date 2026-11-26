import Darwin
import Foundation

/// The nanoseconds in one second.
private let runtimeHealthNanosecondsPerSecond: Double = 1_000_000_000
/// The nanoseconds in one millisecond.
private let runtimeHealthNanosecondsPerMillisecond: UInt64 = 1_000_000
/// The factor that turns a share of one CPU into a percent.
private let runtimeHealthCPUPercentScale = 100.0

/// Judges a soak run from its samples.
public enum ApplicationServiceRuntimeHealthAnalyzer {
  /// The least growth in bytes that counts as growth, however small the first value is.
  public static let minimumMeaningfulGrowthBytes: UInt64 = 8 * 1_024 * 1_024

  /// The summary of `samples` under `policy`; nil when there are no samples.
  ///
  /// The verdict checks the physical footprint limit first, then the resident size limit, then
  /// whether the run is long enough, then memory growth, and last file descriptor and thread
  /// growth. A figure has grown when it rose by more than the larger of
  /// ``minimumMeaningfulGrowthBytes`` and a tenth of its first value, and at least three of four
  /// steps did not decrease.
  public static func summarize(
    _ samples: [RuntimeHealthSample],
    policy: RuntimeHealthPolicy = .standard
  ) -> RuntimeHealthSummary? {
    guard let first = samples.first, let last = samples.last else { return nil }

    let residentValues = samples.map(\.residentBytes)
    let physicalValues = samples.map(\.physicalFootprintBytes)
    let fileDescriptorValues = samples.map(\.fileDescriptorCount)
    let threadValues = samples.map(\.threadCount)
    let minimumResidentBytes = residentValues.min() ?? first.residentBytes
    let peakResidentBytes = residentValues.max() ?? first.residentBytes
    let peakPhysicalFootprintBytes = physicalValues.max() ?? first.physicalFootprintBytes
    let peakFileDescriptorCount = fileDescriptorValues.max() ?? first.fileDescriptorCount
    let peakThreadCount = threadValues.max() ?? first.threadCount
    let residentDeltaBytes = signedDelta(from: first.residentBytes, to: last.residentBytes)
    let physicalFootprintDeltaBytes = signedDelta(
      from: first.physicalFootprintBytes,
      to: last.physicalFootprintBytes
    )
    let elapsedNanoseconds = last.elapsedNanoseconds &- first.elapsedNanoseconds
    let durationSeconds = Double(elapsedNanoseconds) / runtimeHealthNanosecondsPerSecond
    let cpuDelta =
      last.cumulativeCPUNanoseconds >= first.cumulativeCPUNanoseconds
      ? last.cumulativeCPUNanoseconds - first.cumulativeCPUNanoseconds : 0
    let averageCPUPercent =
      elapsedNanoseconds == 0
      ? 0 : Double(cpuDelta) / Double(elapsedNanoseconds) * runtimeHealthCPUPercentScale

    let nondecreasingStepRatio = stepRatio(residentValues)
    let physicalNondecreasingStepRatio = stepRatio(physicalValues)
    let residentMemoryTrend = memoryTrend(
      values: residentValues,
      durationNanoseconds: elapsedNanoseconds,
      nondecreasingStepRatio: nondecreasingStepRatio
    )
    let physicalMemoryTrend = memoryTrend(
      values: physicalValues,
      durationNanoseconds: elapsedNanoseconds,
      nondecreasingStepRatio: physicalNondecreasingStepRatio
    )
    let fileDescriptorDelta = last.fileDescriptorCount - first.fileDescriptorCount
    let threadDelta = last.threadCount - first.threadCount

    let soakVerdict: RuntimeSoakVerdict
    if let limit = policy.maximumPhysicalFootprintBytes, peakPhysicalFootprintBytes > limit {
      soakVerdict = .physicalFootprintLimitExceeded
    } else if let limit = policy.maximumResidentBytes, peakResidentBytes > limit {
      soakVerdict = .residentLimitExceeded
    } else if durationSeconds < Double(policy.minimumSoakSeconds) || samples.count < 5 {
      soakVerdict = .insufficientData
    } else if residentMemoryTrend == .growthObserved || physicalMemoryTrend == .growthObserved {
      soakVerdict = .memoryGrowthObserved
    } else if fileDescriptorDelta >= policy.maximumFileDescriptorGrowth
      || threadDelta >= policy.maximumThreadGrowth
    {
      soakVerdict = .resourceGrowthObserved
    } else {
      soakVerdict = .stable
    }

    return RuntimeHealthSummary(
      sampleCount: samples.count,
      durationSeconds: durationSeconds,
      firstResidentBytes: first.residentBytes,
      lastResidentBytes: last.residentBytes,
      minimumResidentBytes: minimumResidentBytes,
      peakResidentBytes: peakResidentBytes,
      residentDeltaBytes: residentDeltaBytes,
      residentGrowthBytesPerHour: growthRateBytesPerHour(samples: samples, value: \.residentBytes),
      firstPhysicalFootprintBytes: first.physicalFootprintBytes,
      lastPhysicalFootprintBytes: last.physicalFootprintBytes,
      peakPhysicalFootprintBytes: peakPhysicalFootprintBytes,
      physicalFootprintDeltaBytes: physicalFootprintDeltaBytes,
      physicalFootprintGrowthBytesPerHour: growthRateBytesPerHour(
        samples: samples,
        value: \.physicalFootprintBytes
      ),
      firstFileDescriptorCount: first.fileDescriptorCount,
      lastFileDescriptorCount: last.fileDescriptorCount,
      peakFileDescriptorCount: peakFileDescriptorCount,
      fileDescriptorDelta: fileDescriptorDelta,
      firstThreadCount: first.threadCount,
      lastThreadCount: last.threadCount,
      peakThreadCount: peakThreadCount,
      threadDelta: threadDelta,
      averageCPUPercent: averageCPUPercent,
      nondecreasingStepRatio: nondecreasingStepRatio,
      physicalNondecreasingStepRatio: physicalNondecreasingStepRatio,
      memoryTrend: residentMemoryTrend,
      physicalMemoryTrend: physicalMemoryTrend,
      soakVerdict: soakVerdict,
      minimumSoakSeconds: policy.minimumSoakSeconds,
      residentLimitBytes: policy.maximumResidentBytes,
      physicalFootprintLimitBytes: policy.maximumPhysicalFootprintBytes
    )
  }

  /// Whether `values` grew over the run; `insufficientData` below 5 values or without elapsed time.
  private static func memoryTrend(
    values: [UInt64],
    durationNanoseconds: UInt64,
    nondecreasingStepRatio: Double
  ) -> RuntimeMemoryTrend {
    guard let first = values.first, let last = values.last else { return .insufficientData }
    guard values.count >= 5, durationNanoseconds > 0 else { return .insufficientData }
    let delta = signedDelta(from: first, to: last)
    let growthThreshold = max(minimumMeaningfulGrowthBytes, first / 10)
    return delta > Int64(clamping: growthThreshold) && nondecreasingStepRatio >= 0.75
      ? .growthObserved : .stable
  }

  /// The share of steps between neighboring `values` that did not decrease; 0 for fewer than two
  /// values.
  private static func stepRatio<T: Comparable>(_ values: [T]) -> Double {
    let stepCount = max(0, values.count - 1)
    guard stepCount > 0 else { return 0 }
    let nondecreasingSteps = zip(values, values.dropFirst()).filter { $1 >= $0 }.count
    return Double(nondecreasingSteps) / Double(stepCount)
  }

  /// The slope of a least-squares line through the `value` of `samples` over their elapsed time, in
  /// bytes per hour; 0 for fewer than two samples.
  private static func growthRateBytesPerHour(
    samples: [RuntimeHealthSample],
    value: KeyPath<RuntimeHealthSample, UInt64>
  ) -> Double {
    guard samples.count >= 2, let first = samples.first else { return 0 }
    let points = samples.map {
      (
        x: Double($0.elapsedNanoseconds &- first.elapsedNanoseconds)
          / runtimeHealthNanosecondsPerSecond, y: Double($0[keyPath: value])
      )
    }
    let count = Double(points.count)
    let sumX = points.reduce(0) { $0 + $1.x }
    let sumY = points.reduce(0) { $0 + $1.y }
    let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
    let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
    let denominator = count * sumXX - sumX * sumX
    guard denominator != 0 else { return 0 }
    let bytesPerSecond = (count * sumXY - sumX * sumY) / denominator
    return bytesPerSecond * 3_600
  }

  /// The change from `first` to `last`, negative when `last` is smaller.
  private static func signedDelta(from first: UInt64, to last: UInt64) -> Int64 {
    if last >= first { return Int64(clamping: last - first) }
    return -Int64(clamping: first - last)
  }
}

/// Samples a process for a soak run.
public enum ApplicationServiceRuntimeHealthSampler {
  /// The most samples one run takes.
  public static let maximumSampleCount = 100_000
  /// The accepted range of the run length in seconds.
  public static let secondsRange = 1...86_400
  /// The accepted range of the interval between samples in milliseconds.
  public static let intervalMillisecondsRange = 100...60_000

  /// The number of samples a run of `seconds` at `intervalMilliseconds` takes, both ends
  /// included.
  public static func sampleCount(seconds: Int, intervalMilliseconds: Int) -> Int {
    Int(ceil(Double(seconds * 1_000) / Double(intervalMilliseconds))) + 1
  }

  /// Samples the process `processID` every `intervalMilliseconds` for `seconds`, then judges the
  /// run under `policy`.
  ///
  /// It samples at the start and then at each interval until `seconds` have passed.
  ///
  /// - Throws: ``RuntimeHealthSamplingError/invalidConfiguration`` when `seconds` or the interval
  ///   is outside its range, ``RuntimeHealthSamplingError/tooManySamples(_:)`` when the run would
  ///   take too many samples, ``RuntimeHealthSamplingError/processUnavailable(_:)`` when the
  ///   process cannot be read, ``RuntimeHealthSamplingError/noSamples``, and `CancellationError`
  ///   when the task is cancelled.
  public static func sample(
    processID: Int32,
    seconds: Int,
    intervalMilliseconds: Int = 1_000,
    policy: RuntimeHealthPolicy = .standard
  ) async throws -> RuntimeHealthSummary {
    guard secondsRange.contains(seconds), intervalMillisecondsRange.contains(intervalMilliseconds)
    else { throw RuntimeHealthSamplingError.invalidConfiguration }
    let estimatedSampleCount = sampleCount(
      seconds: seconds,
      intervalMilliseconds: intervalMilliseconds
    )
    guard estimatedSampleCount <= maximumSampleCount else {
      throw RuntimeHealthSamplingError.tooManySamples(estimatedSampleCount)
    }

    let durationNanoseconds = UInt64(seconds) * UInt64(runtimeHealthNanosecondsPerSecond)
    let intervalNanoseconds = UInt64(intervalMilliseconds) * runtimeHealthNanosecondsPerMillisecond
    let startedAt = DispatchTime.now().uptimeNanoseconds
    var samples: [RuntimeHealthSample] = []
    samples.reserveCapacity(estimatedSampleCount)

    while true {
      try Task.checkCancellation()
      let now = DispatchTime.now().uptimeNanoseconds
      let usage = try processUsage(processID: processID)
      samples.append(
        RuntimeHealthSample(
          elapsedNanoseconds: now &- startedAt,
          residentBytes: usage.residentBytes,
          physicalFootprintBytes: usage.physicalFootprintBytes,
          cumulativeCPUNanoseconds: usage.cpuNanoseconds,
          fileDescriptorCount: usage.fileDescriptorCount,
          threadCount: usage.threadCount
        )
      )

      let elapsed = now &- startedAt
      if elapsed >= durationNanoseconds { break }
      try await Task.sleep(nanoseconds: min(intervalNanoseconds, durationNanoseconds &- elapsed))
    }

    guard let summary = ApplicationServiceRuntimeHealthAnalyzer.summarize(samples, policy: policy)
    else { throw RuntimeHealthSamplingError.noSamples }
    return summary
  }

  /// The resident size, physical footprint, CPU time, file descriptor count and thread count of the
  /// process `processID`.
  ///
  /// - Throws: ``RuntimeHealthSamplingError/processUnavailable(_:)`` when the system cannot report
  ///   the process.
  private static func processUsage(
    processID: Int32
  ) throws -> (
    residentBytes: UInt64, physicalFootprintBytes: UInt64, cpuNanoseconds: UInt64,
    fileDescriptorCount: Int, threadCount: Int
  ) {
    var usage = rusage_info_v2()
    let usageResult = withUnsafeMutableBytes(of: &usage) { bytes in
      unsafe proc_pid_rusage(
        processID,
        RUSAGE_INFO_V2,
        bytes.baseAddress?.assumingMemoryBound(to: Optional<UnsafeMutableRawPointer>.self)
      )
    }
    guard usageResult == 0 else { throw RuntimeHealthSamplingError.processUnavailable(processID) }

    var taskInfo = proc_taskinfo()
    let taskResult = withUnsafeMutablePointer(to: &taskInfo) {
      unsafe proc_pidinfo(
        processID,
        PROC_PIDTASKINFO,
        0,
        $0,
        Int32(MemoryLayout<proc_taskinfo>.size)
      )
    }
    guard taskResult == Int32(MemoryLayout<proc_taskinfo>.size) else {
      throw RuntimeHealthSamplingError.processUnavailable(processID)
    }

    let fileDescriptorBytes = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, nil, 0)
    guard fileDescriptorBytes >= 0 else {
      throw RuntimeHealthSamplingError.processUnavailable(processID)
    }

    return (
      residentBytes: usage.ri_resident_size, physicalFootprintBytes: usage.ri_phys_footprint,
      cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
      fileDescriptorCount: Int(fileDescriptorBytes) / MemoryLayout<proc_fdinfo>.size,
      threadCount: Int(taskInfo.pti_threadnum)
    )
  }
}
