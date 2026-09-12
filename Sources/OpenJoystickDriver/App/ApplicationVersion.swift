import Foundation
import OpenJoystickDriverKit

enum ApplicationVersion {
  static var current: String { buildIdentity.semanticVersion }

  static var buildIdentity: BuildIdentity { .current() }

  static var display: String { buildIdentity.display }
}
