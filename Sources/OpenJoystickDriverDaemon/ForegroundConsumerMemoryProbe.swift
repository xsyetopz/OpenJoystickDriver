import Darwin
import Foundation
import OpenJoystickDriverKit

struct ForegroundConsumerMemoryProbeResult: Codable {
  let iterations: Int
  let checkpointCount: Int
  let lastConsumerClientCount: Int
  let firstResidentBytes: UInt64
  let lastResidentBytes: UInt64
  let peakResidentBytes: UInt64
  let residentDeltaBytes: Int64
  let firstPhysicalFootprintBytes: UInt64
  let lastPhysicalFootprintBytes: UInt64
  let peakPhysicalFootprintBytes: UInt64
  let physicalFootprintDeltaBytes: Int64
  let physicalMemoryTrend: RuntimeMemoryTrend
}

enum ForegroundConsumerMemoryProbe {
  private struct Usage {
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64
  }

  static func run(iterations: Int) throws -> ForegroundConsumerMemoryProbeResult {
    for _ in 0..<min(20, iterations) {
      _ = ForegroundConsumerOutputMonitor.diagnosticConsumerClientCount()
    }

    let startedAt = DispatchTime.now().uptimeNanoseconds
    var samples = [RuntimeHealthSample]()
    let checkpointStride = max(1, iterations / 20)
    samples.reserveCapacity(22)
    samples.append(sample(startedAt: startedAt, usage: try currentUsage()))
    var lastConsumerClientCount = 0

    for iteration in 1...iterations {
      lastConsumerClientCount =
        ForegroundConsumerOutputMonitor.diagnosticConsumerClientCount()
      if iteration.isMultiple(of: checkpointStride) || iteration == iterations {
        samples.append(sample(startedAt: startedAt, usage: try currentUsage()))
      }
    }

    guard let first = samples.first, let last = samples.last,
      let summary = DaemonRuntimeHealthAnalyzer.summarize(
        samples,
        policy: RuntimeHealthPolicy(
          minimumSoakSeconds: 1,
          maximumPhysicalFootprintBytes: nil
        )
      )
    else {
      throw RuntimeHealthSamplingError.noSamples
    }

    return ForegroundConsumerMemoryProbeResult(
      iterations: iterations,
      checkpointCount: samples.count,
      lastConsumerClientCount: lastConsumerClientCount,
      firstResidentBytes: first.residentBytes,
      lastResidentBytes: last.residentBytes,
      peakResidentBytes: summary.peakResidentBytes,
      residentDeltaBytes: summary.residentDeltaBytes,
      firstPhysicalFootprintBytes: first.physicalFootprintBytes,
      lastPhysicalFootprintBytes: last.physicalFootprintBytes,
      peakPhysicalFootprintBytes: summary.peakPhysicalFootprintBytes,
      physicalFootprintDeltaBytes: summary.physicalFootprintDeltaBytes,
      physicalMemoryTrend: summary.physicalMemoryTrend
    )
  }

  private static func sample(
    startedAt: UInt64,
    usage: Usage
  ) -> RuntimeHealthSample {
    RuntimeHealthSample(
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds &- startedAt,
      residentBytes: usage.residentBytes,
      physicalFootprintBytes: usage.physicalFootprintBytes,
      cumulativeCPUNanoseconds: 0
    )
  }

  private static func currentUsage() throws -> Usage {
    var info = rusage_info_v2()
    let result = withUnsafeMutableBytes(of: &info) { bytes in
      proc_pid_rusage(
        getpid(),
        RUSAGE_INFO_V2,
        bytes.baseAddress?.assumingMemoryBound(
          to: Optional<UnsafeMutableRawPointer>.self
        )
      )
    }
    guard result == 0 else {
      throw RuntimeHealthSamplingError.processUnavailable(getpid())
    }
    return Usage(
      residentBytes: info.ri_resident_size,
      physicalFootprintBytes: info.ri_phys_footprint
    )
  }
}
