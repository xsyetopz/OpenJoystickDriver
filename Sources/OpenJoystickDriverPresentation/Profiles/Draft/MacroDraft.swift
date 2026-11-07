import Foundation
import OpenJoystickDriverKit

/// The kind of a macro step that the editor adds.
enum MacroStepKind: CaseIterable, Identifiable {
  /// Presses and releases a destination at once.
  case tap
  /// Presses a destination and keeps it down.
  case press
  /// Releases a destination that a press step holds.
  case release
  /// Presses destinations together for a time.
  case chord
  /// Waits before the next step.
  case wait

  /// The kind itself.
  var id: Self { self }

  /// The title in the add-step menu.
  var title: String {
    switch self {
    case .tap: OJDLocalized.string("ui.macros.stepTap")
    case .press: OJDLocalized.string("ui.macros.stepPress")
    case .release: OJDLocalized.string("ui.macros.stepRelease")
    case .chord: OJDLocalized.string("ui.macros.stepChord")
    case .wait: OJDLocalized.string("ui.macros.stepWait")
    }
  }

  /// A new step of this kind, with the Space key and a short time as defaults.
  var newStep: RemappingMacroStep {
    let space = RemappingDestination.keyboard(key: .space, modifiers: [])
    switch self {
    case .tap: return .tap(space)
    case .press: return .press(space)
    case .release: return .release(space)
    case .chord: return .chord(destinations: [space], holdMs: 100)
    case .wait: return .wait(durationMs: 100)
    }
  }
}

/// A macro the editor sheet changes before it is saved.
struct MacroDraft: Equatable {
  /// The identifier of the macro; a new macro gets a new one.
  let id: UUID
  /// The name.
  var name: String
  /// The steps in order.
  var steps: [RemappingMacroStep]
  /// How many passes the macro runs.
  var repeatMode: RemappingMacroRepeat
  /// What a press of the source does while the macro runs.
  var whileRunning: RemappingMacroWhileRunning
  /// Whether releasing the source stops the macro.
  var interruptOnRelease: Bool

  /// Creates the draft of `macro`, or of an empty macro with one tap step when nil.
  init(_ macro: RemappingMacro? = nil) {
    id = macro?.id ?? UUID()
    name = macro?.name ?? ""
    steps = macro?.steps ?? [MacroStepKind.tap.newStep]
    repeatMode = macro?.repeatMode ?? .count(1)
    whileRunning = macro?.whileRunning ?? .ignore
    interruptOnRelease = macro?.interruptOnRelease ?? false
  }

  /// The macro with the name trimmed.
  var macro: RemappingMacro {
    RemappingMacro(
      id: id,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      steps: steps,
      repeatMode: repeatMode,
      whileRunning: whileRunning,
      interruptOnRelease: interruptOnRelease
    )
  }

  /// Adds a step of `kind` at the end.
  mutating func addStep(_ kind: MacroStepKind) { steps.append(kind.newStep) }

  /// Moves the step at `index` by `offset` places; a move outside the list does nothing.
  mutating func moveStep(at index: Int, by offset: Int) {
    let target = index + offset
    guard steps.indices.contains(index), steps.indices.contains(target) else { return }
    steps.swapAt(index, target)
  }

  /// Removes the step at `index`.
  mutating func removeStep(at index: Int) {
    guard steps.indices.contains(index) else { return }
    steps.remove(at: index)
  }
}

extension RuntimeProfileDraft {
  /// Returns the draft with `macro` added, or replacing the macro with its identifier.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when the result breaks a profile rule.
  func settingMacro(_ macro: RemappingMacro) throws -> Self {
    var macros = profile.macros
    if let index = macros.firstIndex(where: { $0.id == macro.id }) {
      macros[index] = macro
    } else {
      macros.append(macro)
    }
    return Self(profile: try Self.validate(profile.replacing(macros: macros)))
  }

  /// Returns the draft without the macro.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when an assignment still uses it.
  func removingMacro(_ macroID: UUID) throws -> Self {
    let macros = profile.macros.filter { $0.id != macroID }
    return Self(profile: try Self.validate(profile.replacing(macros: macros)))
  }
}
