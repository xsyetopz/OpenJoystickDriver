import Foundation
import OpenJoystickDriverKit

extension ControllerRecordLayer {
  /// The name of a record layer in the Library list and detail, and in the Controllers detail.
  var libraryTitle: String {
    switch self {
    case .driver: return OJDLocalized.string("ui.library.layer.driver")
    case .bundled: return OJDLocalized.string("ui.library.builtIn")
    case .package: return OJDLocalized.string("ui.library.layer.package")
    case .global: return OJDLocalized.string("ui.library.layer.global")
    case .user: return OJDLocalized.string("ui.library.layer.user")
    case .profile: return OJDLocalized.string("ui.controllers.activeProfile")
    }
  }
}
