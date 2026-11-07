import Foundation

extension ProtocolPacketFixtures {
  /// Switch 2 capture text files in `Switch2/`.
  ///
  /// A file starts with header lines `# key: value`, then one report per line as uppercase hex
  /// pairs separated by single spaces. The headers `controller`, `transport`, `action` and
  /// `source` are required. `source` is `synthetic` for a file built from a source's offsets and
  /// `capture` for one recorded from hardware. Blank lines are skipped.
  public enum Switch2 {
    /// A problem in a capture text file.
    public enum CaptureError: Error, Equatable {
      /// The folder has no file of that name.
      case missing(String)
      /// A header line is not `# key: value`.
      case malformedHeader(line: Int)
      /// A required header is absent.
      case missingHeader(String)
      /// A report line is not uppercase hex pairs.
      case malformedReport(line: Int)
      /// The file holds no report.
      case noReports
    }

    /// One parsed capture text file.
    public struct Capture: Equatable, Sendable {
      /// The headers that every file carries.
      public static let requiredHeaders = ["controller", "transport", "action", "source"]

      /// The header values by key.
      public let headers: [String: String]
      /// The reports, in file order.
      public let reports: [[UInt8]]

      /// The controller, as `VVVV:PPPP`.
      public var controller: String { headers["controller"] ?? "" }
      /// The transport, `usb` or `bluetoothLE`.
      public var transport: String { headers["transport"] ?? "" }
      /// The action the file records.
      public var action: String { headers["action"] ?? "" }
      /// Whether the reports are built from a source's offsets and not recorded from hardware.
      public var isSynthetic: Bool { headers["source"] == "synthetic" }
    }

    /// Parses the text of a capture file.
    ///
    /// - Parameter text: The file text.
    /// - Returns: The headers and reports.
    /// - Throws: ``CaptureError`` for a malformed line, an absent required header or no report.
    public static func parse(_ text: String) throws -> Capture {
      var headers: [String: String] = [:]
      var reports: [[UInt8]] = []
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      for (index, raw) in lines.enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if line.hasPrefix("#") {
          let parts = line.dropFirst().split(separator: ":", maxSplits: 1)
          let key = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
          guard parts.count == 2, !key.isEmpty else {
            throw CaptureError.malformedHeader(line: index + 1)
          }
          headers[key] = parts[1].trimmingCharacters(in: .whitespaces)
        } else {
          reports.append(try bytes(of: line, line: index + 1))
        }
      }
      for key in Capture.requiredHeaders where headers[key] == nil {
        throw CaptureError.missingHeader(key)
      }
      guard !reports.isEmpty else { throw CaptureError.noReports }
      return Capture(headers: headers, reports: reports)
    }

    /// Loads the capture file `name` from the `Switch2` folder.
    ///
    /// - Parameter name: The file name without its `.txt` extension.
    /// - Returns: The parsed file.
    /// - Throws: ``CaptureError``.
    public static func load(_ name: String) throws -> Capture {
      guard
        let url = Bundle.module.url(
          forResource: name,
          withExtension: "txt",
          subdirectory: "Switch2"
        )
      else { throw CaptureError.missing(name) }
      return try parse(String(contentsOf: url, encoding: .utf8))
    }

    private static func bytes(of line: String, line number: Int) throws -> [UInt8] {
      let digits = Set("0123456789ABCDEF")
      let pairs = line.split(separator: " ", omittingEmptySubsequences: false)
      let values = pairs.compactMap { pair -> UInt8? in
        pair.count == 2 && pair.allSatisfy(digits.contains) ? UInt8(pair, radix: 16) : nil
      }
      guard values.count == pairs.count else { throw CaptureError.malformedReport(line: number) }
      return values
    }
  }
}
