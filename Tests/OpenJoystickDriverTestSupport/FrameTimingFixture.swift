public import OpenJoystickDriverKit

extension ControllerFrameTimings {
  /// One controller whose newest frame reached every stage and whose 10-second window of 120
  /// frames had two stalls.
  public static let fixture = ControllerFrameTimings(
    controller: "ctrl-1",
    name: "Pad",
    frames: [
      FrameTiming(
        sequence: 4,
        stages: [
          FrameStageTime(stage: .read, nanoseconds: 100),
          FrameStageTime(stage: .parse, nanoseconds: 150),
          FrameStageTime(stage: .dispatch, nanoseconds: 200),
          FrameStageTime(stage: .deliveryVirtualDevice, nanoseconds: 260),
          FrameStageTime(stage: .deliveryEndpoint, nanoseconds: 900),
        ]
      )
    ],
    summary: FrameTimingSummary(
      lastSeconds: 10,
      frames: 120,
      spanNanoseconds: 119_000_000,
      gaps: [
        FrameGapSummary(
          gap: .readToParse,
          samples: 120,
          p50Nanoseconds: 50_000,
          p99Nanoseconds: 90_000,
          maxNanoseconds: 120_000
        ),
        FrameGapSummary(
          gap: .readToRead,
          samples: 119,
          p50Nanoseconds: 1_000_000,
          p99Nanoseconds: 2_500_000,
          maxNanoseconds: 12_000_000
        ),
      ],
      stalls: FrameStalls(thresholdNanoseconds: 3_000_000, count: 2)
    )
  )
}
