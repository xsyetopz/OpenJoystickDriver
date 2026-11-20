#if canImport(SwiftUI)

  import Combine
  import SwiftUI

  /// Whether any part of a window is on screen.
  ///
  /// A window that hides on close keeps its SwiftUI views and their tasks alive, so a view that
  /// reads the service on a timer gates the timer on this value and costs nothing while the window
  /// is closed, miniaturized, on another Space or covered by other windows.
  @MainActor
  final class WindowVisibility: ObservableObject {
    /// Whether any part of the window is on screen.
    @Published
    private(set) var isVisible: Bool

    /// Creates the visibility with its first value.
    init(isVisible: Bool = false) { self.isVisible = isVisible }

    /// Records whether the window is on screen; an unchanged value publishes nothing.
    func update(_ visible: Bool) {
      if isVisible != visible { isVisible = visible }
    }
  }

  // The key is spelled out instead of using `@Entry`; see `InterfaceLevelEnvironment.swift`.
  private enum WindowVisibleKey: EnvironmentKey {
    static var defaultValue: Bool { true }
  }

  extension EnvironmentValues {
    /// Whether the window that shows the view is on screen; true where no window sets it.
    var ojdWindowVisible: Bool {
      get { self[WindowVisibleKey.self] }
      set { self[WindowVisibleKey.self] = newValue }
    }
  }

  /// Runs a task while the view's window is on screen and restarts it when `id` changes.
  private struct VisibleTaskModifier<ID: Equatable>: ViewModifier {
    /// The task's identity together with the window's visibility.
    private struct Key: Equatable {
      let id: ID
      let visible: Bool
    }

    let id: ID
    let action: @MainActor @Sendable () async -> Void
    @Environment(\.ojdWindowVisible)
    private var visible

    func body(content: Content) -> some View {
      content.task(id: Key(id: id, visible: visible)) {
        if visible { await action() }
      }
    }
  }

  extension View {
    /// Runs `action` while the view is shown and its window is on screen.
    ///
    /// SwiftUI cancels the task when the window leaves the screen and starts it again when the
    /// window returns or `id` changes, so a live reading stops while nobody can see it.
    ///
    /// - Parameters:
    ///   - id: The value whose change restarts the task.
    ///   - action: The work, which returns when it is cancelled.
    /// - Returns: The view with the task attached.
    func ojdTaskWhileVisible<ID: Equatable>(
      id: ID,
      _ action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
      modifier(VisibleTaskModifier(id: id, action: action))
    }

    /// Runs `action` while the view is shown and its window is on screen.
    ///
    /// - Parameter action: The work, which returns when it is cancelled.
    /// - Returns: The view with the task attached.
    func ojdTaskWhileVisible(
      _ action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
      modifier(VisibleTaskModifier(id: 0, action: action))
    }
  }

#endif
