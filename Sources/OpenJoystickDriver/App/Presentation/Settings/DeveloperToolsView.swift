#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperToolsView: View {
    @ObservedObject private var model: DeveloperToolsViewModel

    init(model: DeveloperToolsViewModel) { self.model = model }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PageHeader(
            title: OJDLocalized.string("developer.title", fallback: "Developer"),
            subtitle: OJDLocalized.string(
              "developer.subtitle",
              fallback: "View controller input and USB packets."
            )
          )
          content
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      }.onAppear { model.requestRefresh() }.onDisappear { model.close() }
    }

    @ViewBuilder private var content: some View {
      switch model.loadState {
      case .idle, .loading:
        LoadingStateView(
          message: OJDLocalized.string(
            "developer.loadingControllers",
            fallback: "Loading controller diagnostics..."
          )
        )
      case .noControllers:
        EmptyStateView(
          symbol: "gamecontroller",
          title: OJDLocalized.string(
            "developer.noControllers",
            fallback: "No controllers connected"
          ),
          message: OJDLocalized.string(
            "developer.noControllersDetail",
            fallback: "Connect a controller, then press Refresh."
          )
        )
        Button(OJDLocalized.string("common.refresh", fallback: "Refresh")) {
          Task { @MainActor in await model.refresh() }
        }
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "developer.unavailable",
            fallback: "Developer tools are unavailable"
          ),
          message: message
        ) { Task { @MainActor in await model.refresh() } }
      case .ready:
        DeveloperControllerSummaryView(model: model)
        DeveloperPacketCaptureView(model: model)
        extraInputDiscovery
        diagnosticMode
      }
    }

    private var extraInputDiscovery: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            OJDLocalized.string(
              "developer.extraInputsDescription",
              fallback: "Press one extra button at a time. Detected buttons stay listed until "
                + "you clear the capture."
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )

          if model.observedExtraInputs.isEmpty {
            Text(
              OJDLocalized.string("developer.noExtraInputs", fallback: "No extra buttons detected.")
            ).foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            Text(
              model.observedExtraInputs.map(InputTestButtonPresentation.localizedTitle(for:))
                .joined(separator: ", ")
            ).font(.system(.body, design: .monospaced)).textSelectionIfAvailable()
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("developer.extraInputs", fallback: "Extra Buttons")).font(
          .headline
        )
      }
    }

    private var diagnosticMode: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            OJDSystemSymbol(name: "lock.shield", fallback: "Locked")
            Text(
              OJDLocalized.string(
                "developer.noDiagnosticRecipe",
                fallback: "Diagnostic mode is not available for this controller."
              )
            ).font(.body.weight(.medium))
          }
          Button(
            OJDLocalized.string("developer.enterDiagnosticMode", fallback: "Enter Diagnostic Mode")
          ) {}.disabled(!model.diagnosticRecipeAvailable)
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("developer.diagnosticMode", fallback: "Diagnostic Mode")).font(
          .headline
        )
      }
    }
  }

#endif
