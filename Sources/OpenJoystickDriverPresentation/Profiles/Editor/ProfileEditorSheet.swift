#if os(macOS)
  import Foundation
  import OpenJoystickDriverKit

  /// The sheets that the profile editor opens.
  enum ProfileEditorSheet: Identifiable {
    /// The details sheet.
    case metadata
    /// The motion tuning sheet.
    case motion
    /// The stick mappings sheet.
    case sticks
    /// The trigger mappings sheet.
    case triggers
    /// The touch mappings sheet.
    case touch
    /// The motion tuning sheet of a layer.
    case layerMotion(RemappingLayer)
    /// The sheet that captures a control for a new assignment.
    case capture
    /// The sheet that adjusts the axis tuning of an assignment.
    case adjustment(RemappingBinding)
    /// The sheet that edits the behavior of an assignment.
    case behavior(RemappingBinding)
    /// The sheet that adds a chord.
    case chord
    /// The sheet that adds a sequence.
    case sequence
    /// The sheet that adds a layer.
    case layer
    /// The sheet that adds a macro, or edits the given one.
    case macro(RemappingMacro?)
    /// The sheet that adds an assignment to a layer.
    case layerBinding(RemappingLayer)
    /// The sheet that adjusts the axis tuning of an assignment of a layer, with the layer's
    /// identifier.
    case layerAdjustment(UUID, RemappingBinding)
    /// The sheet that edits the behavior of an assignment of a layer, with the layer's identifier.
    case layerBehavior(UUID, RemappingBinding)

    /// A string that tells the sheets apart, including the layer and assignment of a layer sheet.
    var id: String {
      switch self {
      case .metadata: return "metadata"
      case .motion: return "motion"
      case .sticks: return "sticks"
      case .triggers: return "triggers"
      case .touch: return "touch"
      case .layerMotion(let layer): return "layer-motion-\(layer.id.uuidString)"
      case .capture: return "capture"
      case .adjustment(let binding): return "adjustment-\(binding.id.uuidString)"
      case .behavior(let binding): return "behavior-\(binding.id.uuidString)"
      case .chord: return "chord"
      case .sequence: return "sequence"
      case .layer: return "layer"
      case .macro(let macro): return "macro-\(macro?.id.uuidString ?? "new")"
      case .layerBinding(let layer): return "layer-binding-\(layer.id.uuidString)"
      case .layerAdjustment(let layerID, let binding):
        return "layer-adjustment-\(layerID.uuidString)-\(binding.id.uuidString)"
      case .layerBehavior(let layerID, let binding):
        return "layer-behavior-\(layerID.uuidString)-\(binding.id.uuidString)"
      }
    }
  }

#endif
