#if canImport(AppKit)

  import AppKit

  /// The color role of a status mark, such as the dot or symbol beside a profile or a problem.
  enum SemanticTone: String, CaseIterable, Sendable {
    /// Works and is in a good state; shown in green.
    case positive
    /// Needs the user's attention but does not block; shown in orange.
    case attention
    /// Failed or blocked; shown in red.
    case failure
    /// Carries no judgment; shown in the secondary label color.
    case neutral
    /// Marks the current selection; shown in the system accent color.
    case selection

    /// Alias of ``attention`` for rows that warn about a missing step.
    static let caution = Self.attention

    /// The system color that draws this tone.
    var color: NSColor {
      switch self {
      case .positive: return .systemGreen
      case .attention: return .systemOrange
      case .failure: return .systemRed
      case .neutral: return .secondaryLabelColor
      case .selection: return .controlAccentColor
      }
    }
  }

  /// The state of an item in OJD's lists and banners, which sets its symbol and ``SemanticTone``.
  enum SemanticState: String, CaseIterable, Sendable {
    /// In use, such as the active profile.
    case active
    /// Working and ready.
    case healthy
    /// Needs the user's attention.
    case attention
    /// Failed or blocked.
    case failure
    /// Present but not in use, such as a profile that is not active.
    case inactive
    /// Waiting for a result.
    case loading
    /// No controller or service connection.
    case disconnected
    /// State that OJD cannot read.
    case unknown
    /// Holds edits that are not saved.
    case dirty
    /// Holds no unsaved edits.
    case saved
    /// Recording an input, such as a captured button press.
    case capturing

    /// The symbol and tone that draw this state.
    var presentation: SemanticStatePresentation {
      switch self {
      case .active: return .init(tone: .positive, symbolName: "checkmark.circle.fill")
      case .healthy: return .init(tone: .positive, symbolName: "checkmark.circle")
      case .attention: return .init(tone: .attention, symbolName: "exclamationmark.triangle")
      case .failure: return .init(tone: .failure, symbolName: "xmark.octagon")
      case .inactive: return .init(tone: .neutral, symbolName: "circle")
      case .loading: return .init(tone: .neutral, symbolName: "clock")
      case .disconnected: return .init(tone: .neutral, symbolName: "cable.connector.slash")
      case .unknown: return .init(tone: .neutral, symbolName: "questionmark.circle")
      case .dirty: return .init(tone: .attention, symbolName: "pencil.circle")
      case .saved: return .init(tone: .positive, symbolName: "checkmark.circle")
      case .capturing: return .init(tone: .positive, symbolName: "record.circle")
      }
    }
  }

  /// The SF Symbol and tone that draw a ``SemanticState``.
  struct SemanticStatePresentation: Equatable, Sendable {
    /// The color role of the mark.
    let tone: SemanticTone
    /// The name of the SF Symbol to draw.
    let symbolName: String
  }

  /// How a symbol request resolves: a symbol that exists on this Mac, or text instead.
  enum SystemSymbolResolution: Equatable, Sendable {
    /// Draw the SF Symbol with this name.
    case symbol(String)
    /// Draw text, because neither symbol exists on this Mac.
    case text
  }

  /// Chooses between a preferred SF Symbol, its fallback and plain text.
  enum SystemSymbolPolicy {
    /// Returns the preferred symbol when it exists, else the fallback when it exists, else text.
    static func resolution(
      preferred: String,
      fallback: String?,
      preferredIsAvailable: Bool,
      fallbackIsAvailable: Bool
    ) -> SystemSymbolResolution {
      if preferredIsAvailable { return .symbol(preferred) }
      if let fallback, fallbackIsAvailable { return .symbol(fallback) }
      return .text
    }
  }

#endif
