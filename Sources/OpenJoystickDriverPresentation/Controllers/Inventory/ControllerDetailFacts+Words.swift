import Foundation
import OpenJoystickDriverKit

/// The words of the technical facts under Advanced, each with the raw identifier beside it.
extension ControllerDetailFacts {
  /// Returns the words with the raw identifier beside them, such as `Left stick (LeftStickX)`.
  ///
  /// - Parameters:
  ///   - words: The words a person reads.
  ///   - identifier: The raw identifier the CLI, the files and the service use.
  /// - Returns: The words with the raw identifier beside them.
  static func withIdentifier(_ words: String, _ identifier: String) -> String {
    OJDLocalized.formatted("ui.controllers.withIdentifier", words, identifier)
  }

  /// Returns the parser as words, with its `ojd` spelling beside it.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The parser as words, with its `ojd` spelling beside it.
  static func parserText(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    let name = device.protocolBinding.commandLineName
    guard !name.isEmpty else { return .none }
    return .text(withIdentifier(device.protocolBinding.displayName, name))
  }

  /// Returns the input mapping as words, with the name of its source beside it.
  ///
  /// - Parameter mapping: The input mapping the binding result reports.
  /// - Returns: The input mapping as words, with the name of its source beside it.
  static func inputMappingText(_ mapping: InputMapping) -> String {
    let words: String
    switch mapping.source {
    case .sdlGameControllerDB, .none:
      let key =
        mapping.source == .none
        ? "cli.controller.show.inputMappingUnbound" : "cli.controller.show.inputMappingSDL"
      words = String(
        format: OJDLocalized.string(key),
        mapping.match.map(matchTierText) ?? "",
        mapping.guid ?? ""
      )
    case .record, .standardHIDUsageMap: words = mapping.rowText(localize: OJDLocalized.string)
    }
    return withIdentifier(words, mapping.source.rawValue)
  }

  /// Returns what a database line matched on, in words.
  ///
  /// - Parameter tier: The tier at which the line matched.
  /// - Returns: What a database line matched on, in words.
  static func matchTierText(_ tier: SDLMatchTier) -> String {
    switch tier {
    case .exactGUID: return OJDLocalized.string("ui.controllers.sdlMatch.exactGUID")
    case .guidWithoutNameCRC:
      return OJDLocalized.string("ui.controllers.sdlMatch.guidWithoutNameCRC")
    case .guidWithoutVersion:
      return OJDLocalized.string("ui.controllers.sdlMatch.guidWithoutVersion")
    case .guidWithoutVersionAndNameCRC:
      return OJDLocalized.string("ui.controllers.sdlMatch.guidWithoutVersionAndNameCRC")
    }
  }

  /// Returns a control as words, with the name the files and the service use beside it, such as
  /// `D-pad Up (DpadUp)`. A name that is already the raw name, such as `Start`, shows once.
  ///
  /// - Parameter control: The control.
  /// - Returns: A control as words, with its raw name beside it.
  static func controlText(_ control: Control) -> String {
    let words = controlName(control)
    return words == control.rawValue ? words : withIdentifier(words, control.rawValue)
  }

  /// Returns the words that name a control.
  ///
  /// - Parameter control: The control.
  /// - Returns: The words that name a control.
  static func controlName(_ control: Control) -> String {
    switch control {
    case .dpadUp: return OJDLocalized.string("ui.inputTest.dpadUp")
    case .dpadDown: return OJDLocalized.string("ui.inputTest.dpadDown")
    case .dpadLeft: return OJDLocalized.string("ui.inputTest.dpadLeft")
    case .dpadRight: return OJDLocalized.string("ui.inputTest.dpadRight")
    case .leftStickX: return RuntimePresentation.axisLabel(.leftStickX)
    case .leftStickY: return RuntimePresentation.axisLabel(.leftStickY)
    case .rightStickX: return RuntimePresentation.axisLabel(.rightStickX)
    case .rightStickY: return RuntimePresentation.axisLabel(.rightStickY)
    case .auxiliary7: return OJDLocalized.string("ui.controllers.control.auxiliary7")
    case .auxiliary8: return OJDLocalized.string("ui.controllers.control.auxiliary8")
    case .leftStickTouch: return OJDLocalized.string("ui.controllers.control.leftStickTouch")
    case .rightStickTouch: return OJDLocalized.string("ui.controllers.control.rightStickTouch")
    case .leftTrackpadTouch:
      return OJDLocalized.string("ui.controllers.control.leftTrackpadTouch")
    case .rightTrackpadTouch:
      return OJDLocalized.string("ui.controllers.control.rightTrackpadTouch")
    case .pointerX: return OJDLocalized.string("ui.controllers.control.pointerX")
    case .pointerY: return OJDLocalized.string("ui.controllers.control.pointerY")
    case .pointerTracking: return OJDLocalized.string("ui.controllers.control.pointerTracking")
    case .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
      .back, .start, .leftStickClick, .rightStickClick, .guide, .capture, .microphone,
      .touchpadClick, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2, .auxiliary1,
      .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .leftTrackpadClick,
      .rightTrackpadClick, .leftGripTouch, .rightGripTouch:
      return RuntimePresentation.buttonLabel(control)
    }
  }
}
