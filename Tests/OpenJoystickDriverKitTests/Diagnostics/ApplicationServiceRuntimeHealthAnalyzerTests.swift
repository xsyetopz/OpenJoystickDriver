import Testing

@testable import OpenJoystickDriverKit

struct ApplicationServiceRuntimeHealthAnalyzerTests {
  private let mib: UInt64 = 1_024 * 1_024

  @Test func stableWindowAllowsNoiseAndTransientPeaks() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(residentMiB: [100, 150, 101, 99, 101], cpuMilliseconds: [0, 10, 20, 30, 40])
      )
    )

    #expect(summary.memoryTrend == .stable)
    #expect(summary.peakResidentBytes == 150 * mib)
    #expect(summary.residentDeltaBytes == Int64(mib))
    #expect(summary.averageCPUPercent == 1)
    #expect(summary.soakVerdict == .insufficientData)
  }

  @Test func significantMostlyMonotonicGrowthIsFlagged() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(
          residentMiB: [100, 103, 107, 112, 121],
          physicalMiB: [80, 83, 87, 92, 101],
          cpuMilliseconds: [0, 5, 10, 15, 20],
          elapsedSeconds: [0, 15, 30, 45, 60]
        )
      )
    )

    #expect(summary.memoryTrend == .growthObserved)
    #expect(summary.physicalMemoryTrend == .growthObserved)
    #expect(summary.residentDeltaBytes == Int64(21 * mib))
    #expect(summary.nondecreasingStepRatio == 1)
    #expect(summary.soakVerdict == .memoryGrowthObserved)
    #expect(summary.residentGrowthBytesPerHour > Double(1_200 * mib))
  }

  @Test func stableLongSoakProducesStableVerdictAndResourceRanges() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(
          residentMiB: [100, 100, 100, 100, 100],
          physicalMiB: [85, 85, 85, 85, 85],
          cpuMilliseconds: [0, 100, 200, 300, 400],
          elapsedSeconds: [0, 15, 30, 45, 60],
          fileDescriptors: [12, 13, 12, 12, 12],
          threads: [5, 6, 5, 5, 5]
        )
      )
    )

    #expect(summary.soakVerdict == .stable)
    #expect(summary.peakFileDescriptorCount == 13)
    #expect(summary.fileDescriptorDelta == 0)
    #expect(summary.peakThreadCount == 6)
    #expect(summary.threadDelta == 0)
    #expect(abs(summary.residentGrowthBytesPerHour) < Double(mib))
  }

  @Test func descriptorOrThreadGrowthIsAResourceFinding() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(
          residentMiB: [100, 100, 100, 100, 100],
          cpuMilliseconds: [0, 10, 20, 30, 40],
          elapsedSeconds: [0, 15, 30, 45, 60],
          fileDescriptors: [10, 20, 30, 40, 42],
          threads: [4, 4, 4, 4, 4]
        )
      )
    )

    #expect(summary.fileDescriptorDelta == 32)
    #expect(summary.soakVerdict == .resourceGrowthObserved)
  }

  @Test func configuredResidentHighWaterLimitTakesPriority() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(residentMiB: [100, 110, 120, 130, 140], cpuMilliseconds: [0, 10, 20, 30, 40]),
        policy: RuntimeHealthPolicy(maximumResidentBytes: 128 * mib)
      )
    )

    #expect(summary.peakResidentBytes == 140 * mib)
    #expect(summary.residentLimitBytes == 128 * mib)
    #expect(summary.soakVerdict == .residentLimitExceeded)
  }

  @Test func defaultPhysicalFootprintLimitFlagsCompressedOrDirtyAllocatorGrowth() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(
          residentMiB: [100, 100, 100, 100, 100],
          physicalMiB: [700, 700, 700, 700, 700],
          cpuMilliseconds: [0, 10, 20, 30, 40]
        )
      )
    )

    #expect(summary.physicalFootprintLimitBytes == 512 * mib)
    #expect(summary.soakVerdict == .physicalFootprintLimitExceeded)
  }

  @Test func tooFewSamplesRemainInconclusive() throws {
    let summary = try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(
        samples(residentMiB: [100, 120, 140, 160], cpuMilliseconds: [0, 5, 10, 15])
      )
    )

    #expect(summary.memoryTrend == .insufficientData)
    #expect(summary.soakVerdict == .insufficientData)
  }

  @Test func emptyInputProducesNoSummary() {
    #expect(ApplicationServiceRuntimeHealthAnalyzer.summarize([]) == nil)
  }

  private func samples(
    residentMiB: [UInt64],
    physicalMiB: [UInt64]? = nil,
    cpuMilliseconds: [UInt64],
    elapsedSeconds: [UInt64]? = nil,
    fileDescriptors: [Int]? = nil,
    threads: [Int]? = nil
  ) -> [RuntimeHealthSample] {
    residentMiB.indices.map { index in
      RuntimeHealthSample(
        elapsedNanoseconds: (elapsedSeconds?[index] ?? UInt64(index)) * 1_000_000_000,
        residentBytes: residentMiB[index] * mib,
        physicalFootprintBytes: (physicalMiB?[index] ?? residentMiB[index]) * mib,
        cumulativeCPUNanoseconds: cpuMilliseconds[index] * 1_000_000,
        fileDescriptorCount: fileDescriptors?[index] ?? 10,
        threadCount: threads?[index] ?? 4
      )
    }
  }
}
