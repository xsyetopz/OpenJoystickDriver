#if canImport(AppKit)

  import AppKit

  /// Applies the Show in Dock setting.
  ///
  /// One rule decides the policy: the app has a Dock icon (`.regular`) while Show in Dock is on or
  /// any window is open, and none (`.accessory`) otherwise.
  ///
  /// An app that switches from `.accessory` to `.regular` while it is active shows its menu bar,
  /// but AppKit does not track its menus until the app is activated again after another app was
  /// active. Activating an app that is already active does nothing, so after such a switch the
  /// controller hands activation to the Dock and takes it back once the app resigned active. An
  /// app that is inactive at the switch needs no hand-off: its next activation, such as the one
  /// of the window that opens, follows another app being active.
  @MainActor
  final class DockIconController {
    /// A window of the app whose open state keeps the Dock icon.
    enum Window: Hashable {
      /// The main window.
      case workbench
      /// The Input Test window.
      case inputTest
      /// The Settings window.
      case settings
    }

    /// The outcome of asking the Dock to become the active app.
    enum DockActivation: Equatable {
      /// The Dock accepted the request to become active.
      case requested
      /// The Dock is not running.
      case notRunning
      /// The Dock refused the request.
      case refused
    }

    /// The AppKit calls of the activation hand-off.
    struct Activation {
      /// Whether the app is the active app.
      var isActive: @MainActor () -> Bool
      /// Asks the Dock to become the active app.
      var activateDock: @MainActor () -> DockActivation
      /// Makes the app the active app.
      var activateApp: @MainActor () -> Void
      /// Calls the handler each time the app resigns active, until the returned stop runs.
      var observeResignActive: @MainActor (@escaping @MainActor () -> Void) -> @MainActor () -> Void
    }

    /// Sets the app's activation policy and returns whether macOS accepted it.
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    /// The AppKit calls of the activation hand-off.
    private let activation: Activation
    /// The windows that are open now.
    private var openWindows: Set<Window> = []
    /// Ends the pending hand-off; set from the request to the Dock until the app resigns active
    /// or switches to `.accessory`.
    private var stopHandOff: (@MainActor () -> Void)?
    /// The Show in Dock setting.
    var showsAlways = false {
      didSet { reconcile() }
    }
    /// The activation policy that macOS accepted last.
    ///
    /// It starts as `.accessory`.
    private(set) var appliedPolicy = NSApplication.ActivationPolicy.accessory

    /// Creates the controller with the call that sets the policy and the hand-off calls.
    init(
      setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool,
      activation: Activation
    ) {
      self.setActivationPolicy = setActivationPolicy
      self.activation = activation
    }

    /// The controller of the running app.
    static func appKit() -> DockIconController {
      DockIconController(
        setActivationPolicy: { NSApplication.shared.setActivationPolicy($0) },
        activation: .appKit
      )
    }

    /// Whether the app waits to resign active to the Dock and then activates itself.
    var isHandingOffActivation: Bool { stopHandOff != nil }

    /// Records that `window` is open or closed and applies the policy that follows.
    func setOpen(_ window: Window, _ isOpen: Bool) {
      if isOpen { openWindows.insert(window) } else { openWindows.remove(window) }
      reconcile()
    }

    /// Applies the activation policy that Show in Dock and the open windows ask for.
    ///
    /// When macOS refuses the change, the applied policy stays as it was, the refusal goes to
    /// standard error, and the next setting or window change tries again.
    private func reconcile() {
      let desiredPolicy: NSApplication.ActivationPolicy =
        showsAlways || !openWindows.isEmpty ? .regular : .accessory
      guard desiredPolicy != appliedPolicy else { return }
      guard setActivationPolicy(desiredPolicy) else {
        fputs(
          "macOS refused the Dock icon change to \(desiredPolicy); "
            + "the next window or setting change retries it.\n",
          stderr
        )
        return
      }
      appliedPolicy = desiredPolicy
      if desiredPolicy == .regular {
        handOffActivationIfActive()
      } else {
        // An app without a window that resigns active stays inactive.
        endHandOff()
      }
    }

    /// Starts the hand-off of activation to the Dock when the app is active, and ends a pending
    /// one.
    private func handOffActivationIfActive() {
      endHandOff()
      guard activation.isActive() else { return }
      stopHandOff = activation.observeResignActive { [weak self] in
        guard let self else { return }
        self.endHandOff()
        self.activation.activateApp()
      }
      let outcome = activation.activateDock()
      guard outcome != .requested else { return }
      endHandOff()
      fputs(
        "\(outcome == .notRunning ? "The Dock is not running" : "The Dock refused activation"); "
          + "the menu bar menus open after the app is activated again.\n",
        stderr
      )
    }

    /// Stops observing the app resigning active and clears the pending hand-off.
    private func endHandOff() {
      stopHandOff?()
      stopHandOff = nil
    }
  }

  extension DockIconController.Activation {
    /// The calls that act on the running app and the Dock through AppKit.
    static var appKit: Self {
      Self(
        isActive: { NSApplication.shared.isActive },
        activateDock: {
          guard
            let dock = NSRunningApplication.runningApplications(
              withBundleIdentifier: "com.apple.dock"
            ).first
          else { return .notRunning }
          return dock.activate(options: []) ? .requested : .refused
        },
        // `activate()` of macOS 14 is a request that another app has to yield for, and the Dock
        // does not yield; this call activates the app regardless of the active app.
        activateApp: { AppForeground.activate() },
        observeResignActive: { handler in
          let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
          ) { _ in MainActor.assumeIsolated { handler() } }
          return { NotificationCenter.default.removeObserver(observer) }
        }
      )
    }
  }

#endif
