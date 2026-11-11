#if canImport(SwiftUI)

  import SwiftUI

  /// The Claim button of a controller that Apple's driver holds.
  ///
  /// It sends the extension activation request, as `ojd controller claim` does for such a model,
  /// and is disabled while that request runs.
  struct ControllerClaimButton: View {
    /// The model of the app's view of the service, which sends the request.
    @ObservedObject
    var viewModel: RuntimeViewModel

    /// The button.
    var body: some View {
      Button(OJDLocalized.string("ui.controllers.claim")) {
        Task { @MainActor in await viewModel.repairSystemExtension() }
      }.disabled(viewModel.systemExtensionSetupState == .running)
    }
  }

#endif
