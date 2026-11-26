import Foundation

/// Whether a memory figure grew over a soak run.
public enum RuntimeMemoryTrend: String, Codable, Sendable {
  /// The run has fewer than 5 samples or no elapsed time.
  case insufficientData
  /// The figure did not grow beyond the allowance.
  case stable
  /// The figure grew beyond the allowance, and at least three of four steps did not decrease.
  case growthObserved
}

/// What a soak run says about the service, from the most serious cause down.
public enum RuntimeSoakVerdict: String, Codable, CaseIterable, Sendable {
  /// The run is shorter than the policy's minimum or has fewer than 5 samples.
  case insufficientData
  /// No limit was exceeded and nothing grew.
  case stable
  /// The resident size or the physical footprint grew.
  case memoryGrowthObserved
  /// The file descriptor count or the thread count grew by the policy's limit or more.
  case resourceGrowthObserved
  /// The peak resident size is above the policy's limit.
  case residentLimitExceeded
  /// The peak physical footprint is above the policy's limit.
  case physicalFootprintLimitExceeded
}

/// The limits that a soak run is judged by.
public struct RuntimeHealthPolicy: Codable, Equatable, Sendable {
  /// The policy that `ojd diagnose` uses unless the user sets memory limits.
  public static let standard = Self()

  /// The least seconds a run must last to be judged; at least 1.
  public let minimumSoakSeconds: Int
  /// The resident size above which the run fails; nil for no limit.
  public let maximumResidentBytes: UInt64?
  /// The physical footprint above which the run fails; nil for no limit.
  public let maximumPhysicalFootprintBytes: UInt64?
  /// The file descriptor growth at which the run counts as growing; at least 1.
  public let maximumFileDescriptorGrowth: Int
  /// The thread growth at which the run counts as growing; at least 1.
  public let maximumThreadGrowth: Int

  /// Creates a policy; the defaults are 60 seconds, no resident limit, a footprint limit of 512
  /// MiB, and growth limits of 32 file descriptors and 8 threads.
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

  /// The accepted range of a memory limit in MiB; 0 means no limit.
  public static let limitMiBRange = 0...65_536

  /// The standard policy with memory limits in MiB, where 0 means no limit.
  public init(residentLimitMiB: Int, footprintLimitMiB: Int) {
    func bytes(_ mebibytes: Int) -> UInt64? {
      mebibytes == 0 ? nil : UInt64(mebibytes) * 1_048_576
    }
    self.init(
      maximumResidentBytes: bytes(residentLimitMiB),
      maximumPhysicalFootprintBytes: bytes(footprintLimitMiB)
    )
  }
}

/// One reading of the service process.
public struct RuntimeHealthSample: Codable, Sendable, Equatable {
  /// The time since the run began, in nanoseconds.
  public let elapsedNanoseconds: UInt64
  /// The resident size in bytes.
  public let residentBytes: UInt64
  /// The physical footprint in bytes.
  public let physicalFootprintBytes: UInt64
  /// The CPU time the process has used so far, user and system together, in nanoseconds.
  public let cumulativeCPUNanoseconds: UInt64
  /// The number of open file descriptors.
  public let fileDescriptorCount: Int
  /// The number of threads.
  public let threadCount: Int

  /// Creates a sample from its values.
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

/// What a soak run measured and how it judged the run.
public struct RuntimeHealthSummary: Codable, Sendable, Equatable {
  /// The number of samples.
  public let sampleCount: Int
  /// The time from the first sample to the last, in seconds.
  public let durationSeconds: Double
  /// The resident size of the first sample in bytes.
  public let firstResidentBytes: UInt64
  /// The resident size of the last sample in bytes.
  public let lastResidentBytes: UInt64
  /// The smallest resident size in bytes.
  public let minimumResidentBytes: UInt64
  /// The largest resident size in bytes.
  public let peakResidentBytes: UInt64
  /// The resident size of the last sample minus that of the first, in bytes.
  public let residentDeltaBytes: Int64
  /// The slope of a straight line fitted to the resident sizes, in bytes per hour.
  public let residentGrowthBytesPerHour: Double
  /// The physical footprint of the first sample in bytes.
  public let firstPhysicalFootprintBytes: UInt64
  /// The physical footprint of the last sample in bytes.
  public let lastPhysicalFootprintBytes: UInt64
  /// The largest physical footprint in bytes.
  public let peakPhysicalFootprintBytes: UInt64
  /// The physical footprint of the last sample minus that of the first, in bytes.
  public let physicalFootprintDeltaBytes: Int64
  /// The slope of a straight line fitted to the physical footprints, in bytes per hour.
  public let physicalFootprintGrowthBytesPerHour: Double
  /// The file descriptor count of the first sample.
  public let firstFileDescriptorCount: Int
  /// The file descriptor count of the last sample.
  public let lastFileDescriptorCount: Int
  /// The largest file descriptor count.
  public let peakFileDescriptorCount: Int
  /// The file descriptor count of the last sample minus that of the first.
  public let fileDescriptorDelta: Int
  /// The thread count of the first sample.
  public let firstThreadCount: Int
  /// The thread count of the last sample.
  public let lastThreadCount: Int
  /// The largest thread count.
  public let peakThreadCount: Int
  /// The thread count of the last sample minus that of the first.
  public let threadDelta: Int
  /// The CPU time used over the run as a percent of one CPU.
  public let averageCPUPercent: Double
  /// The share of steps between two resident sizes that did not decrease.
  public let nondecreasingStepRatio: Double
  /// The share of steps between two physical footprints that did not decrease.
  public let physicalNondecreasingStepRatio: Double
  /// Whether the resident size grew.
  public let memoryTrend: RuntimeMemoryTrend
  /// Whether the physical footprint grew.
  public let physicalMemoryTrend: RuntimeMemoryTrend
  /// The verdict on the run.
  public let soakVerdict: RuntimeSoakVerdict
  /// The policy's minimum run length in seconds.
  public let minimumSoakSeconds: Int
  /// The policy's resident size limit; nil for no limit.
  public let residentLimitBytes: UInt64?
  /// The policy's physical footprint limit; nil for no limit.
  public let physicalFootprintLimitBytes: UInt64?
}
