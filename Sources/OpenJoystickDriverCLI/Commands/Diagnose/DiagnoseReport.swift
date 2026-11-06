import Foundation
import OpenJoystickDriverKit

/// The `ojd diagnose --json` result.
///
/// `output` is absent unless `--output` wrote a file. `timings` holds the newest per-stage frame
/// timestamps and the window summary of each connected controller; it is empty when the service is
/// stopped or has no frames.
struct DiagnoseReport: Encodable, Equatable {
  /// The result of each check.
  let checks: [DiagnoseCheck]
  /// The frame timings of each connected controller.
  let timings: [ControllerFrameTimings]
  /// The path of the support report, when `--output` wrote one.
  let output: String?

  /// The number of checks that failed.
  var failureCount: Int { checks.filter { $0.status == .fail }.count }

  /// One `id`, `status`, `detail` row per check, then the `timing-summary` rows of each
  /// controller, then one `timing`, controller, sequence, stage, nanoseconds row per recorded
  /// stage.
  var plainRows: [[String]] {
    checks.map { [$0.id, CommandLineName.kebab($0.status.rawValue), $0.detail] }
      + timings.flatMap(Self.summaryRows)
      + timings.flatMap { controller in
        controller.frames.flatMap { frame in
          frame.stages.map {
            [
              "timing", controller.controller, String(frame.sequence),
              CommandLineName.kebab($0.stage.rawValue),
              String($0.nanoseconds),
            ]
          }
        }
      }
  }

  /// The `timing-summary` rows of `controller`.
  ///
  /// The first two columns are `timing-summary` and the controller ID; the third names the row, and
  /// the columns after it depend on the name:
  ///
  /// - `window`: frames in the window, time span in nanoseconds, the seconds of `--frames` (empty
  ///   for the whole ring).
  /// - a gap name in kebab-case (`read-to-parse`, `parse-to-dispatch`,
  ///   `dispatch-to-delivery-virtual-device`, `dispatch-to-delivery-endpoint`, `read-to-read`):
  ///   samples, median, 99th percentile and maximum in nanoseconds. A gap without a sample has no
  ///   row; the whole ring has no `read-to-read` row.
  /// - `stalls`: threshold in nanoseconds, read intervals longer than the threshold. The row is
  ///   absent for the whole ring and when the window holds fewer than two frames.
  private static func summaryRows(of controller: ControllerFrameTimings) -> [[String]] {
    let summary = controller.summary
    let head = ["timing-summary", controller.controller]
    var rows = [
      head + [
        "window", String(summary.frames), String(summary.spanNanoseconds),
        summary.lastSeconds.map(String.init) ?? "",
      ]
    ]
    rows += summary.gaps.map {
      head + [
        CommandLineName.kebab($0.gap.rawValue), String($0.samples), String($0.p50Nanoseconds),
        String($0.p99Nanoseconds), String($0.maxNanoseconds),
      ]
    }
    if let stalls = summary.stalls {
      rows.append(head + ["stalls", String(stalls.thresholdNanoseconds), String(stalls.count)])
    }
    return rows
  }

  /// The human summary block of `controller`: a header, one line per gap, and the stall line.
  static func summaryLines(of controller: ControllerFrameTimings) -> [String] {
    let summary = controller.summary
    var lines = [
      CLILocalized.format(
        "cli.diagnose.group.timingsSummaryHeader",
        controller.name,
        controller.controller,
        String(summary.frames),
        milliseconds(summary.spanNanoseconds)
      )
    ]
    lines += summary.gaps.map {
      "  "
        + CLILocalized.format(
          "cli.diagnose.group.timingsSummaryGap",
          CommandLineName.kebab($0.gap.rawValue),
          milliseconds($0.p50Nanoseconds),
          milliseconds($0.p99Nanoseconds),
          milliseconds($0.maxNanoseconds),
          String($0.samples)
        )
    }
    if let stalls = summary.stalls {
      lines.append(
        "  "
          + CLILocalized.format(
            "cli.diagnose.group.timingsSummaryStalls",
            String(stalls.count),
            milliseconds(stalls.thresholdNanoseconds),
            String(FrameTimingSummary.stallIntervalMultiplier)
          )
      )
    } else if summary.lastSeconds == nil {
      lines.append("  " + CLILocalized.text("cli.diagnose.group.timingsSummaryStallsNeedFrames"))
    } else {
      lines.append("  " + CLILocalized.text("cli.diagnose.group.timingsSummaryNoStalls"))
    }
    return lines
  }

  /// `nanoseconds` in milliseconds with three decimals and a point, whatever the locale.
  private static func milliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
  }
}
