import Darwin
import Foundation

public enum RuntimeMemoryTrend: String, Codable, Sendable {
  case insufficientData
  case stable
  case growthObserved
}

public enum RuntimeSoakVerdict: String, Codable, Sendable {
  case insufficientData
  case stable
  case memoryGrowthObserved
  case resourceGrowthObserved
  case residentLimitExceeded
  case physicalFootprintLimitExceeded
}

public struct RuntimeHealthPolicy: Codable, Equatable, Sendable {
  public static let standard = Self()

  public let minimumSoakSeconds: Int
  public let maximumResidentBytes: UInt64?
  public let maximumPhysicalFootprintBytes: UInt64?
  public let maximumFileDescriptorGrowth: Int
  public let maximumThreadGrowth: Int

  public init(
    minimumSoakSeconds: Int = 60,
    maximumResidentBytes: UInt64? = nil,
    maximumPhysicalFootprintBytes: UInt64? = 512 * 1_024 * 1_024,
    maximumFileDescriptorGrowth: Int = 32,
    maximumThreadGrowth: Int = 8
  ) {
    self.minimumSoakSeconds = max(1, minimumSoakSeconds)
    self.maximumResidentBytes = maximumResidentBytes
    self.maximumPhysicalFootprintBytes = maximumPhysicalFootprintBytes
    self.maximumFileDescriptorGrowth = max(1, maximumFileDescriptorGrowth)
    self.maximumThreadGrowth = max(1, maximumThreadGrowth)
  }
}

public struct RuntimeHealthSample: Codable, Sendable, Equatable {
  public let elapsedNanoseconds: UInt64
  public let residentBytes: UInt64
  public let physicalFootprintBytes: UInt64
  public let cumulativeCPUNanoseconds: UInt64
  public let fileDescriptorCount: Int
  public let threadCount: Int

  public init(
    elapsedNanoseconds: UInt64,
    residentBytes: UInt64,
    physicalFootprintBytes: UInt64 = 0,
    cumulativeCPUNanoseconds: UInt64,
    fileDescriptorCount: Int = 0,
    threadCount: Int = 0
  ) {
    self.elapsedNanoseconds = elapsedNanoseconds
    self.residentBytes = residentBytes
    self.physicalFootprintBytes = physicalFootprintBytes
    self.cumulativeCPUNanoseconds = cumulativeCPUNanoseconds
    self.fileDescriptorCount = fileDescriptorCount
    self.threadCount = threadCount
  }
}

public struct RuntimeHealthSummary: Codable, Sendable, Equatable {
  public let sampleCount: Int
  public let durationSeconds: Double
  public let firstResidentBytes: UInt64
  public let lastResidentBytes: UInt64
  public let minimumResidentBytes: UInt64
  public let peakResidentBytes: UInt64
  public let residentDeltaBytes: Int64
  public let residentGrowthBytesPerHour: Double
  public let firstPhysicalFootprintBytes: UInt64
  public let lastPhysicalFootprintBytes: UInt64
  public let peakPhysicalFootprintBytes: UInt64
  public let physicalFootprintDeltaBytes: Int64
  public let physicalFootprintGrowthBytesPerHour: Double
  public let firstFileDescriptorCount: Int
  public let lastFileDescriptorCount: Int
  public let peakFileDescriptorCount: Int
  public let fileDescriptorDelta: Int
  public let firstThreadCount: Int
  public let lastThreadCount: Int
  public let peakThreadCount: Int
  public let threadDelta: Int
  public let averageCPUPercent: Double
  public let nondecreasingStepRatio: Double
  public let physicalNondecreasingStepRatio: Double
  public let memoryTrend: RuntimeMemoryTrend
  public let physicalMemoryTrend: RuntimeMemoryTrend
  public let soakVerdict: RuntimeSoakVerdict
  public let minimumSoakSeconds: Int
  public let residentLimitBytes: UInt64?
  public let physicalFootprintLimitBytes: UInt64?
}

public enum ApplicationServiceRuntimeHealthAnalyzer {
  public static let minimumMeaningfulGrowthBytes: UInt64 = 8 * 1_024 * 1_024

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
    let peakPhysicalFootprintBytes =
      physicalValues.max() ?? first.physicalFootprintBytes
    let peakFileDescriptorCount =
      fileDescriptorValues.max() ?? first.fileDescriptorCount
    let peakThreadCount = threadValues.max() ?? first.threadCount
    let residentDeltaBytes = signedDelta(
      from: first.residentBytes,
      to: last.residentBytes
    )
    let physicalFootprintDeltaBytes = signedDelta(
      from: first.physicalFootprintBytes,
      to: last.physicalFootprintBytes
    )
    let elapsedNanoseconds = last.elapsedNanoseconds &- first.elapsedNanoseconds
    let durationSeconds = Double(elapsedNanoseconds) / 1_000_000_000
    let cpuDelta =
      last.cumulativeCPUNanoseconds >= first.cumulativeCPUNanoseconds
      ? last.cumulativeCPUNanoseconds - first.cumulativeCPUNanoseconds
      : 0
    let averageCPUPercent =
      elapsedNanoseconds == 0
      ? 0
      : Double(cpuDelta) / Double(elapsedNanoseconds) * 100

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
    if let limit = policy.maximumPhysicalFootprintBytes,
      peakPhysicalFootprintBytes > limit
    {
      soakVerdict = .physicalFootprintLimitExceeded
    } else if let limit = policy.maximumResidentBytes, peakResidentBytes > limit {
      soakVerdict = .residentLimitExceeded
    } else if durationSeconds < Double(policy.minimumSoakSeconds) || samples.count < 5 {
      soakVerdict = .insufficientData
    } else if residentMemoryTrend == .growthObserved
      || physicalMemoryTrend == .growthObserved
    {
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
      residentGrowthBytesPerHour: growthRateBytesPerHour(
        samples: samples,
        value: \.residentBytes
      ),
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

  private static func memoryTrend(
    values: [UInt64],
    durationNanoseconds: UInt64,
    nondecreasingStepRatio: Double
  ) -> RuntimeMemoryTrend {
    guard let first = values.first, let last = values.last else {
      return .insufficientData
    }
    guard values.count >= 5, durationNanoseconds > 0 else {
      return .insufficientData
    }
    let delta = signedDelta(from: first, to: last)
    let growthThreshold = max(minimumMeaningfulGrowthBytes, first / 10)
    return delta > Int64(clamping: growthThreshold) && nondecreasingStepRatio >= 0.75
      ? .growthObserved
      : .stable
  }

  private static func stepRatio<T: Comparable>(_ values: [T]) -> Double {
    let stepCount = max(0, values.count - 1)
    guard stepCount > 0 else { return 0 }
    let nondecreasingSteps = zip(values, values.dropFirst()).filter { $1 >= $0 }.count
    return Double(nondecreasingSteps) / Double(stepCount)
  }

  private static func growthRateBytesPerHour(
    samples: [RuntimeHealthSample],
    value: KeyPath<RuntimeHealthSample, UInt64>
  ) -> Double {
    guard samples.count >= 2, let first = samples.first else { return 0 }
    let points = samples.map {
      (
        x: Double($0.elapsedNanoseconds &- first.elapsedNanoseconds) / 1_000_000_000,
        y: Double($0[keyPath: value])
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

  private static func signedDelta(from first: UInt64, to last: UInt64) -> Int64 {
    if last >= first {
      return Int64(clamping: last - first)
    }
    return -Int64(clamping: first - last)
  }
}

public enum RuntimeHealthSamplingError: LocalizedError, Sendable {
  case processUnavailable(Int32)
  case invalidConfiguration
  case tooManySamples(Int)
  case noSamples

  public var errorDescription: String? {
    switch self {
    case .processUnavailable(let pid):
      return "Could not read runtime information for application service process \(pid)."
    case .invalidConfiguration:
      return "Runtime sampling requires 1...86400 seconds and a 100...60000 ms interval."
    case .tooManySamples(let count):
      return "Runtime sampling would collect \(count) samples; increase the interval."
    case .noSamples:
      return "No application service runtime samples were collected."
    }
  }
}

public enum ApplicationServiceRuntimeHealthSampler {
  public static let maximumSampleCount = 100_000

  public static func sample(
    processID: Int32,
    seconds: Int,
    intervalMilliseconds: Int = 1_000,
    policy: RuntimeHealthPolicy = .standard
  ) async throws -> RuntimeHealthSummary {
    guard (1...86_400).contains(seconds),
      (100...60_000).contains(intervalMilliseconds)
    else {
      throw RuntimeHealthSamplingError.invalidConfiguration
    }
    let estimatedSampleCount =
      Int(ceil(Double(seconds * 1_000) / Double(intervalMilliseconds))) + 1
    guard estimatedSampleCount <= maximumSampleCount else {
      throw RuntimeHealthSamplingError.tooManySamples(estimatedSampleCount)
    }

    let durationNanoseconds = UInt64(seconds) * 1_000_000_000
    let intervalNanoseconds = UInt64(intervalMilliseconds) * 1_000_000
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
      try await Task.sleep(
        nanoseconds: min(intervalNanoseconds, durationNanoseconds &- elapsed)
      )
    }

    guard
      let summary = ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples,
        policy: policy
      )
    else {
      throw RuntimeHealthSamplingError.noSamples
    }
    return summary
  }

  private static func processUsage(
    processID: Int32
  ) throws -> (
    residentBytes: UInt64,
    physicalFootprintBytes: UInt64,
    cpuNanoseconds: UInt64,
    fileDescriptorCount: Int,
    threadCount: Int
  ) {
    var usage = rusage_info_v2()
    let usageResult = withUnsafeMutableBytes(of: &usage) { bytes in
      proc_pid_rusage(
        processID,
        RUSAGE_INFO_V2,
        bytes.baseAddress?.assumingMemoryBound(to: Optional<UnsafeMutableRawPointer>.self)
      )
    }
    guard usageResult == 0 else {
      throw RuntimeHealthSamplingError.processUnavailable(processID)
    }

    var taskInfo = proc_taskinfo()
    let taskResult = withUnsafeMutablePointer(to: &taskInfo) {
      proc_pidinfo(
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

    let fileDescriptorBytes = proc_pidinfo(
      processID,
      PROC_PIDLISTFDS,
      0,
      nil,
      0
    )
    guard fileDescriptorBytes >= 0 else {
      throw RuntimeHealthSamplingError.processUnavailable(processID)
    }

    return (
      residentBytes: usage.ri_resident_size,
      physicalFootprintBytes: usage.ri_phys_footprint,
      cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
      fileDescriptorCount:
        Int(fileDescriptorBytes) / MemoryLayout<proc_fdinfo>.size,
      threadCount: Int(taskInfo.pti_threadnum)
    )
  }
}
