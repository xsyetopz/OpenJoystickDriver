#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The form sections of the developer tools: Controller, Raw Packet Capture and Extra Buttons.
  ///
  /// They sit in the Advanced pane's form, which scrolls. The Settings window controller starts and
  /// stops the reads.
  struct DeveloperToolsView: View {
    /// The state of the developer tools.
    @ObservedObject
    private var model: DeveloperToolsViewModel

    /// Creates the sections on a model.
    init(model: DeveloperToolsViewModel) { self.model = model }

    /// The developer tools content for the current load state.
    var body: some View {
      content
    }

    /// The sections that match the load state.
    @ViewBuilder
    private var content: some View {
      switch model.loadState {
      case .idle:
        Section(OJDLocalized.string("ui.developer.controllerDetails")) {
          Text(OJDLocalized.string("ui.developer.notLoaded")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          refreshButton
        }
      case .loading:
        Section {
          Text(OJDLocalized.string("ui.developer.loadingControllers")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
      case .noControllers:
        Section(OJDLocalized.string("ui.developer.controllerDetails")) {
          Text(OJDLocalized.string("ui.developer.noControllers"))
          Text(OJDLocalized.string("ui.developer.noControllersDetail")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          refreshButton
        }
      case .unavailable(let message):
        Section(OJDLocalized.string("ui.developer.controllerDetails")) {
          Text(OJDLocalized.string("ui.developer.unavailable"))
          Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
          refreshButton
        }
      case .ready:
        DeveloperControllerSummaryView(model: model)
        DeveloperPacketCaptureView(model: model)
        extraInputDiscovery
      }
    }

    /// The Refresh button, which reads the controllers again.
    private var refreshButton: some View {
      Button(OJDLocalized.string("action.refresh")) {
        Task { @MainActor in await model.refresh() }
      }.help(OJDLocalized.string("ui.help.refreshControllers"))
    }

    /// The Extra Buttons section: the controls pressed beyond the core set.
    private var extraInputDiscovery: some View {
      Section(OJDLocalized.string("ui.developer.extraInputs")) {
        Text(OJDLocalized.string("ui.developer.extraInputsDescription")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        if model.observedExtraInputs.isEmpty {
          Text(OJDLocalized.string("ui.developer.noExtraInputs")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        } else {
          Text(
            model.observedExtraInputs.map(InputTestButtonPresentation.localizedTitle)
              .joined(separator: ", ")
          ).textSelection(.enabled)
        }
      }
    }
  }

#endif
