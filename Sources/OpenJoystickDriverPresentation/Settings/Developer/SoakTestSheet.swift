#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Soak Test section of the developer tools: what the test does and the button that opens
  /// its sheet, which runs `ojd diagnose --soak`.
  struct DeveloperSoakTestSection: View {
    /// The soak test that the sheet runs.
    @ObservedObject
    var model: SoakTestModel
    /// Whether the Soak Test sheet is open.
    @State
    private var showsSheet = false

    /// The Soak test section: a description and the button that opens the sheet.
    var body: some View {
      Section(OJDLocalized.string("ui.developer.soakTest")) {
        Text(OJDLocalized.string("ui.developer.soakTestDescription")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        Button(OJDLocalized.string("ui.developer.soakTestOpen")) { showsSheet = true }
          .sheet(isPresented: $showsSheet) { SoakTestSheet(model: model) }
      }
    }
  }

  /// Asks for the soak test's duration, sample interval and memory limits, runs the test and shows
  /// its result as pass, warning, failure or skip.
  struct SoakTestSheet: View {
    /// The soak test that the sheet runs.
    @ObservedObject
    var model: SoakTestModel
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode

    /// The title, the content of the test and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.developer.soakTest")).font(.headline)
        content
        HStack {
          Spacer()
          buttons
        }
      }.ojdSheet(.compact)
    }

    /// Closes the sheet after a result; Done and Escape both end here.
    private func dismissFinishedResult() {
      guard case .finished = model.state else { return }
      model.reset()
      presentationMode.wrappedValue.dismiss()
    }

    /// A text field titled and labeled with the name of `field`.
    private func field(_ field: SoakTestField, _ text: Binding<String>) -> some View {
      let title = OJDLocalized.string(field.labelKey)
      return TextField(title, text: text).ojdAccessibilityLabel(title)
    }

    /// The entry fields, the running indicator or the result, as the state of the test says.
    @ViewBuilder
    private var content: some View {
      switch model.state {
      case .idle:
        Form {
          field(.seconds, $model.form.seconds)
          field(.interval, $model.form.interval)
          field(.residentLimit, $model.form.residentLimit)
          field(.footprintLimit, $model.form.footprintLimit)
          Text(OJDLocalized.string("ui.developer.soakLimitHint")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          if let problem = model.problem {
            Text(problem.message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }
        }
      case .running:
        HStack(spacing: OJDSpacing.small) {
          ProgressView().controlSize(.small)
          Text(OJDLocalized.string("ui.developer.soakRunning"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
      case .finished(let row):
        VStack(alignment: .leading, spacing: OJDSpacing.small) {
          Label {
            Text(OJDLocalized.string(row.statusKey)).font(.headline)
          } icon: {
            Image(systemName: row.symbolName).foregroundColor(
              ActivityDiagnosticsView.color(of: row.status)
            )
          }
          Text(row.detail).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    /// The buttons of the state: Cancel and Start while the numbers are asked for, Stop while a run
    /// is in progress, and Start and Done after a result.
    @ViewBuilder
    private var buttons: some View {
      switch model.state {
      case .idle:
        Button(OJDLocalized.string("action.cancel")) { presentationMode.wrappedValue.dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(OJDLocalized.string("ui.developer.soakStart")) { model.start() }
          .keyboardShortcut(.defaultAction).disabled(model.problem != nil)
      case .running:
        Button(OJDLocalized.string("action.stop")) { model.cancel() }
          .keyboardShortcut(.cancelAction)
      case .finished:
        Button(OJDLocalized.string("ui.developer.soakStart")) {
          model.reset()
          model.start()
        }
        Button(OJDLocalized.string("action.done")) { dismissFinishedResult() }
          .keyboardShortcut(.defaultAction)
        // Escape works without a focused control; the button is for the shortcut only.
        Button("") { dismissFinishedResult() }.keyboardShortcut(.cancelAction).frame(
          width: 0,
          height: 0
        ).opacity(0).accessibilityHidden(true)
      }
    }
  }

#endif
