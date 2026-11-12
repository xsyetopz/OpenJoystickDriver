#if canImport(SwiftUI)

  import OpenJoystickDriverKit
  import SwiftUI

  extension EnvironmentValues {
    /// How much of the interface shows; the main window sets it from the Settings preference.
    @Entry
    var ojdInterfaceLevel = InterfaceLevel.default
  }

#endif
