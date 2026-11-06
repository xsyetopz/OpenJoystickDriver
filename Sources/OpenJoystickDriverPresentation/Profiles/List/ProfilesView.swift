#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Profiles area of the main window: the list of profiles and the editor of the selected
  /// profile.
  struct ProfilesView: View {
    /// The model of the app's view of the service.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The profile library, whose changes the screen starts and follows.
    @ObservedObject
    var library: ProfileLibraryModel
    /// The main window's selection of area and profile.
    @ObservedObject
    var navigation: MainWindowNavigationModel
    /// The state of the Profiles screen.
    @ObservedObject
    var screen: ProfilesViewModel
    /// The column of the main window that the screen fills.
    let column: MainWindowColumn
  }

#endif
