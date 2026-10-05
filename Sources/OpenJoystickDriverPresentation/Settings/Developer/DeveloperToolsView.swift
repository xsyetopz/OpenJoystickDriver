#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperToolsView: View {
    @ObservedObject
    private var model: DeveloperToolsViewModel

    init(model: DeveloperToolsViewModel) { self.model = model }

    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            PageHeader(
              title: OJDLocalized.string("developer.title"),
              subtitle: OJDLocalized.string(
                "developer.subtitle"
              )
            )
            content(compact: proxy.size.width < 760)
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.onAppear { model.requestRefresh() }.onDisappear { model.close() }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
      switch model.loadState {
      case .idle, .loading:
        LoadingStateView(
          message: OJDLocalized.string(
            "developer.loadingControllers"
          )
        )
      case .noControllers:
        EmptyStateView(
          symbol: "gamecontroller",
          title: OJDLocalized.string(
            "developer.noControllers"
          ),
          message: OJDLocalized.string(
            "developer.noControllersDetail"
          )
        )
        Button(OJDLocalized.string("common.refresh")) {
          Task { @MainActor in await model.refresh() }
        }
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "developer.unavailable"
          ),
          message: message
        ) { Task { @MainActor in await model.refresh() } }
      case .ready:
        DeveloperControllerSummaryView(model: model, compact: compact)
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
              "developer.extraInputsDescription"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )

          if model.observedExtraInputs.isEmpty {
            Text(
              OJDLocalized.string("developer.noExtraInputs")
            ).foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            Text(
              model.observedExtraInputs.map {
                InputTestButtonPresentation.localizedTitle(
                  for: $0,
                  labels: model.selectedButtonLabels
                )
              }.joined(separator: ", ")
            ).font(.system(.body, design: .monospaced)).textSelection(.enabled)
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("developer.extraInputs")).font(
          .headline
        )
      }
    }

    private var diagnosticMode: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            OJDSystemSymbol(name: "lock.shield", fallback: nil)
            Text(
              OJDLocalized.string(
                "developer.noDiagnosticRecipe"
              )
            ).font(.body.weight(.medium))
          }
          Button(
            OJDLocalized.string("developer.enterDiagnosticMode")
          ) {}.disabled(!model.diagnosticRecipeAvailable)
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("developer.diagnosticMode")).font(
          .headline
        )
      }
    }
  }

#endif
