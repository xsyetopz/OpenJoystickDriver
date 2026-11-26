import Foundation
import OpenJoystickDriverKit

/// One labelled fact of the Controllers detail.
struct ControllerFact: Equatable, Identifiable {
  /// What a fact says, which names the row.
  enum Kind: Hashable {
    /// The app in front that selected the profile in force.
    case profileSelectedBy
    /// Whether a virtual device publishes the controller.
    case publication
    /// Whether a `Pause` has the controller pass through unmapped.
    case paused
    /// The route that serves the controller.
    case serving
    /// The serial number.
    case serialNumber
    /// The health of the input session.
    case inputHealth
    /// The battery level.
    case battery
    /// Whether the controller charges.
    case chargingState
    /// Whether the controller is on a cable, while its charging state is unknown.
    case cableState
    /// The report mode of a Wii Remote.
    case wiiReportMode
    /// The extension plugged into a Wii Remote.
    case wiiExtension
    /// The Motion Plus state of a Wii Remote.
    case wiiMotionPlus
    /// The rumble motors.
    case rumble
    /// The lighting features.
    case lighting
    /// The adaptive triggers.
    case adaptiveTriggers
    /// Whether the controller has a motion sensor.
    case motion
    /// The number of touch contacts.
    case touchContacts
    /// The unit ID.
    case unitID
    /// The binding that parses the controller's input.
    case parser
    /// Who owns the controller's input and output.
    case ownership
    /// The concern of the physical ownership, when the system does not list the controller too.
    case duplicateExposureRisk
    /// Where the controller's record comes from.
    case record
    /// Where the HID usage map comes from.
    case inputMapping
    /// The controls the parser sends.
    case controls
    /// How the startup commands went.
    case startupStatus
    /// The format of the input reports.
    case inputReportFormat
    /// How many times the input recovered.
    case inputRecoveries
    /// When the last publication was attempted.
    case publicationAttempted
    /// When the last publication completed.
    case publicationCompleted
    /// The vendor and product ID.
    case usbIdentifier
    /// The endpoint that sends input.
    case inputEndpoint
    /// The endpoint that takes output.
    case outputEndpoint
    /// The client that holds the controller for itself.
    case exclusiveOwner
    /// Every process that holds the controller open.
    case holders
    /// Whether the system also lists the controller.
    case alsoListedBySystem
  }

  /// What the fact says.
  let kind: Kind
  /// The localized name of the fact.
  let label: String
  /// The value of the fact.
  let value: OJDValue

  /// The kind, which names the fact.
  var id: Kind { kind }
}
