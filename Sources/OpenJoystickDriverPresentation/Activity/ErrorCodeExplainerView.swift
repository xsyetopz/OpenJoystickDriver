#if canImport(AppKit) && canImport(SwiftUI)

  import Combine
  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Holds the code that the user typed in the Explain Error Code sheet and the answer.
  @MainActor
  final class ErrorCodeExplainerModel: ObservableObject {
    /// Whether the main window shows the Explain Error Code sheet.
    @Published
    var isPresented = false
    /// The code that the user typed.
    @Published
    var typedCode = ""
    /// The answer for the typed code, or nil before the first lookup.
    @Published
    private(set) var answer: ErrorCodeExplanation?

    /// Looks up the typed code.
    func explain() { answer = ErrorCodeExplanation.lookup(typedCode) }
  }

  /// The Explain Error Code sheet: the text `ojd explain` prints for a code.
  struct ErrorCodeExplainerView: View {
    /// Holds the typed code and the answer.
    @ObservedObject
    private var model: ErrorCodeExplainerModel

    /// Creates the sheet on `model`.
    init(model: ErrorCodeExplainerModel) { self.model = model }

    /// The title, the code field, the answer and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(OJDLocalized.string("ui.console.explain.title")).font(.headline)
        TextField(OJDLocalized.string("ui.console.explain.prompt"), text: $model.typedCode) {
          model.explain()
        }.ojdAccessibilityLabel(OJDLocalized.string("ui.console.explain.prompt"))
        answer.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.done")) { model.isPresented = false }
            .keyboardShortcut(.cancelAction)
          Button(OJDLocalized.string("ui.console.explain.action")) { model.explain() }
            .keyboardShortcut(.defaultAction)
            .disabled(model.typedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.ojdSheet(.compact)
    }

    /// The answer for the typed code: its facts and explanation, a note that the code is unknown,
    /// or nothing before the first lookup.
    @ViewBuilder
    private var answer: some View {
      switch model.answer {
      case .explained(let facts)?:
        VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
          Text(facts.code).font(.system(.body, design: .monospaced))
          ForEach(Self.factLines(facts), id: \.self) { line in
            Text(line).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
          Text(facts.explanation).textSelection(.enabled).fixedSize(
            horizontal: false,
            vertical: true
          ).padding(.top, 4)
        }
      case .unknown(let typed)?:
        Text(OJDLocalized.formatted("cli.explain.group.unknown", typed)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
      case nil: EmptyView()
      }
    }
  }

  extension ErrorCodeExplainerView {
    /// The labeled lines that `ojd explain` prints between the code and the explanation.
    static func factLines(_ facts: ErrorCodeFacts) -> [String] {
      var lines = [OJDLocalized.formatted("cli.explain.group.area", facts.area)]
      if let exitCode = facts.exitCode {
        lines.append(OJDLocalized.formatted("cli.explain.group.exitCode", String(exitCode)))
      }
      if let wire = facts.wire {
        lines.append(OJDLocalized.formatted("cli.explain.group.wire", wire))
      }
      return lines
    }
  }

  /// Presents the Explain Error Code sheet over the window that holds it.
  struct ErrorCodeExplainerSheetHost: View {
    /// The model of the sheet.
    @ObservedObject
    var model: ErrorCodeExplainerModel

    /// An invisible host of the sheet that presents the explainer while the model says so.
    var body: some View {
      Color.clear.sheet(isPresented: $model.isPresented) { ErrorCodeExplainerView(model: model) }
    }
  }

#endif
