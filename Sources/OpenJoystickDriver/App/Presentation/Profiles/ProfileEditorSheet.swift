#if os(macOS)
  import Foundation
  import OpenJoystickDriverKit

  enum ProfileEditorSheet: Identifiable {
    case metadata
    case motion
    case sticks
    case triggers
    case touch
    case layerMotion(RemappingLayer)
    case capture
    case adjustment(RemappingBinding)
    case behavior(RemappingBinding)
    case chord
    case sequence
    case layer
    case layerBinding(RemappingLayer)
    case layerAdjustment(UUID, RemappingBinding)
    case layerBehavior(UUID, RemappingBinding)

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
      case .layerBinding(let layer): return "layer-binding-\(layer.id.uuidString)"
      case .layerAdjustment(let layerID, let binding):
        return "layer-adjustment-\(layerID.uuidString)-\(binding.id.uuidString)"
      case .layerBehavior(let layerID, let binding):
        return "layer-behavior-\(layerID.uuidString)-\(binding.id.uuidString)"
      }
    }
  }

#endif
