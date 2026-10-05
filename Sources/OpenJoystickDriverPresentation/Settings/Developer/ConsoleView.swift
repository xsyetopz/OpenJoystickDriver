#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  enum ConsoleStreamSelection: String, CaseIterable, Identifiable {
    case all
    case standardOutput
    case standardError

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all: return OJDLocalized.string("console.all")
      case .standardOutput: return OJDLocalized.string("console.output")
      case .standardError: return OJDLocalized.string("console.errors")
      }
    }
  }

  @MainActor
  final class ConsoleViewModel: ObservableObject {
    @Published
    var selection: ConsoleStreamSelection = .all
    @Published
    private(set) var snapshots: [ApplicationServiceLogSnapshot] = []
    @Published
    private(set) var errorMessage: String?

    var displayedLines: [String] {
      snapshots.flatMap { snapshot -> [String] in
        guard selection.includes(snapshot.stream) else { return [] }
        let prefix = snapshot.stream == .standardOutput ? "OUT" : "ERR"
        return snapshot.lines.flatMap { ConsoleLineWrapper.wrap("[\(prefix)] \($0)") }
      }
    }

    func refresh() {
      do {
        snapshots = try ApplicationServiceLogStream.allCases.map {
          try ApplicationServiceLogService.tail(stream: $0, maximumLines: 500)
        }
        errorMessage = nil
      } catch { errorMessage = error.localizedDescription }
    }

    func copyAll() {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(displayedLines.joined(separator: "\n"), forType: .string)
    }
  }

  enum ConsoleLineWrapper {
    static let defaultColumns = 80

    static func wrap(_ line: String, columns: Int = defaultColumns) -> [String] {
      guard columns > 0, line.count > columns else { return [line] }
      var result: [String] = []
      var current = ""

      for word in line.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
        if current.isEmpty {
          append(word, columns: columns, result: &result, remainder: &current)
        } else if current.count + 1 + word.count <= columns {
          current += " \(word)"
        } else {
          result.append(current)
          current = ""
          append(word, columns: columns, result: &result, remainder: &current)
        }
      }
      if !current.isEmpty { result.append(current) }
      return result.isEmpty ? [""] : result
    }

    private static func append(
      _ word: String,
      columns: Int,
      result: inout [String],
      remainder: inout String
    ) {
      var remaining = word[...]
      while remaining.count > columns {
        let end = remaining.index(remaining.startIndex, offsetBy: columns)
        result.append(String(remaining[..<end]))
        remaining = remaining[end...]
      }
      remainder = String(remaining)
    }
  }

  extension ConsoleStreamSelection {
    func includes(_ stream: ApplicationServiceLogStream) -> Bool {
      switch self {
      case .all: return true
      case .standardOutput: return stream == .standardOutput
      case .standardError: return stream == .standardError
      }
    }
  }

  struct ConsoleView: View {
    @ObservedObject
    private var model: ConsoleViewModel

    init(model: ConsoleViewModel = ConsoleViewModel()) { self.model = model }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          PageHeader(title: OJDLocalized.string("console.title"))
          Spacer()
          Picker(
            OJDLocalized.string("console.stream"),
            selection: $model.selection
          ) {
            ForEach(ConsoleStreamSelection.allCases) { selection in
              Text(selection.title).tag(selection)
            }
          }.pickerStyle(.segmented).frame(width: 220)
          OJDCompactSymbolButton(
            symbolName: "arrow.clockwise",
            label: OJDLocalized.string("common.refresh"),
            action: model.refresh
          )
          OJDCompactSymbolButton(
            symbolName: "doc.on.doc",
            label: OJDLocalized.string("console.copyAll"),
            action: model.copyAll
          ).disabled(model.displayedLines.isEmpty)
        }

        if let errorMessage = model.errorMessage {
          ServiceFailureStateView(
            title: OJDLocalized.string("console.loadError"),
            message: errorMessage,
            retry: model.refresh
          )
        } else {
          ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
              if model.displayedLines.isEmpty {
                Text(OJDLocalized.string("console.empty"))
                  .foregroundColor(Color(NSColor.secondaryLabelColor)).padding(12)
              } else {
                ForEach(Array(model.displayedLines.enumerated()), id: \.offset) { _, line in
                  Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
              }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
          }.background(Color(NSColor.textBackgroundColor)).overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor))
          )
        }

        Text(ApplicationServiceLogService.sharingWarning).font(.caption).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        )
      }.padding(24).onAppear { model.refresh() }
    }
  }

#endif
